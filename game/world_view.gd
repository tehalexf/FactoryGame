## Draws the Simulation. A reader, never a writer.
##
## ADR 0001 makes Godot a renderer only, so every number here comes out of a
## `query_*` call on the tick it is drawn and is thrown away again. There is no
## mirror of Simulation state on this side — no list of Machines, no cached counts —
## because a mirror is a second copy of the truth and the first thing to drift from
## it. The meshes below are the one thing this node owns, and they are a function of
## the queries, rebuilt whenever what the queries report stops matching them.
##
## Machines, the Nest and the Belts draw the bodies `tools/assets/generate_machines.sh`
## generated for them, out of `assets/machines/<id>.glb`. A body the pipeline has not
## produced yet falls back to a box sized from its footprint, so **adding a row to
## `content/machines.csv` is never blocked on art** — the Machine is simply plain until
## someone draws it. What matters either way is that the thing on screen is in the place
## the Simulation says it is, and that the count on screen is the count in the buffer.
##
## Nodes, Breaches and the hologram stay boxes on purpose: a Node is ground rather than a
## building, a Breach is a hole, and the hologram is a promise.
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

## How high above the ground a gauge hangs over a Machine, before
## `AMMUNITION_GAUGE_LIFT_METRES` is added. Taller than any housing in the content, so an
## ammunition or Charge gauge clears the roof of whatever it belongs to.
##
## **Not a claim about how tall a Machine is.** That is `height_metres` in
## `content/machines.csv`, which the Simulation collides against and
## `query_machine_height_metres` reports — a placeholder box is sized from *that*, so what a
## player walks onto and what they can see are one number.
const MACHINE_GAUGE_HEIGHT_METRES: float = 3.0

## A Node is drawn as a low slab, so a Miner standing on one does not hide it.
const NODE_HEIGHT_METRES: float = 0.4

## How high a tile of Belt stands when it has no generated body — a low slab, so the
## Items riding it are what the eye follows.
const BELT_HEIGHT_METRES: float = 0.3

## How much of a tile a Wall fills. A shade under the full 2 m so neighbouring Walls read as
## separate blocks rather than as one extruded slab.
const WALL_WIDTH_FRACTION: float = 0.92

## A Wall at full health, and one chewed to nothing. The fill between them is how far gone it
## is, because a Wall's health is the one thing a player needs to read off it at a distance.
const WALL_WHOLE: Color = Color(0.30, 0.31, 0.32)
const WALL_RUINED: Color = Color(0.52, 0.22, 0.17)

## How high the deck of a generated tile of Belt is, in metres, which is where an Item
## rides. Declared by the `belt_straight` ports in `content/machine_ports.csv`, which the
## asset suite holds the mesh to; this is presentation only — where an Item *is* is the
## Simulation's answer, and only how high off the ground it is drawn comes from here.
const BELT_DECK_METRES: float = 0.9

## An Item is a small cube sitting on the Belt. Smaller than the 0.5 m an Item occupies
## along the run, so a packed Belt reads as a queue of distinct boxes with gaps rather
## than as one continuous bar — which is the whole point of drawing them.
const ITEM_SIZE_METRES: float = 0.35

## Which player this view is looking through. One for now; co-op makes it the local id.
const VIEWED_PLAYER: int = 0

## Where the generated bodies live, and the ids of the two that are not Machines. Every
## body in that directory comes out of `tools/assets/generate_machines.sh`, which models
## it with its origin at the centre of its footprint and its feet on the ground — so a
## body needs only to be moved to a tile centre to be standing in the right place.
const BODY_DIRECTORY: String = "res://assets/machines/"

## The Nest's body. Generated from the `nest` row of `content/machine_bodies.csv` like
## every other, even though the Nest is not a Machine.
const NEST_BODY: String = "nest"

## One tile of Belt. Modelled running along +z — its input port faces north and its
## output south — so a tile is turned by the direction its run goes in.
const BELT_BODY: String = "belt_straight"

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

## A Breach that has been announced but has not opened yet, drawn as a thin bright frame on
## the ground where it will be.
##
## Deliberately a *different* marker from a Breach rather than a dimmer one: "a hole is about
## to appear here" and "there is a hole here" ask a player for different things, and a warning
## that looks like a faded version of the real thing is a warning that reads as a rendering
## artefact. Brighter than the Breach it becomes, because the point is to be noticed from
## across the Factory while there is still time to put a Turret in the way.
const PENDING_BREACH_HEIGHT_METRES: float = 0.35

## How big a Crawler is, in metres. Smaller than a 2 m tile, so a swarm packed into a
## chokepoint still reads as a number of individuals.
const ENEMY_SIZE_METRES: float = 0.9

## How big a Siege Hulk is, in metres. Twice a tile across, because the one threat the Factory
## cannot answer has to read as *the* thing on the horizon from the moment it appears — a boss a
## player has to squint at is a boss they will not go out to meet.
const SIEGE_HULK_SIZE_METRES: float = 4.0

## The armoured front and the open rear of a Siege Hulk.
##
## **Two meshes and two materials, because the weak point has to be discoverable by looking.**
## The whole shape of this fight is that the front shrugs off 85% of a hit and the back does not,
## and nothing anywhere tells a player that in words — so the hull is cast iron and the vent on
## the back glows. A player who empties half a magazine into the front and then walks round is
## the player this geometry is for.
const SIEGE_HULK_HULL: Color = Color(0.17, 0.18, 0.19)
const SIEGE_HULK_VENT: Color = Color(0.95, 0.42, 0.10)

## How big a Hive is, in metres, and what colour. A mound rather than a building: it is the
## Enemy's, not the players', so it reads as grown rather than welded.
const HIVE_SIZE_METRES: float = 4.0
const HIVE_COLOUR: Color = Color(0.29, 0.20, 0.26)

## A shell's impact marker: a flat ring of ground, as thin as a Breach's slab and as wide as
## `siege_hulk.shell_blast_radius_metres` across.
##
## **The marker is the Telegraph, and it is drawn from the Simulation's own impact point** — so
## what a player dodges is literally where the damage will be rather than an approximation of it.
## It brightens as the shell comes down, because a static marker reads as scenery and the thing
## a player needs is the sense of a countdown.
const SHELL_MARKER_HEIGHT_METRES: float = 0.12
const SHELL_MARKER_FAR: Color = Color(0.55, 0.30, 0.10, 0.55)
const SHELL_MARKER_NEAR: Color = Color(1.00, 0.30, 0.15, 0.85)

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

## The Charge gauge's colours. Blue-white, so artillery reads as a different quantity from
## Ammunition at a glance rather than after reading the number — and the backing goes red on an
## empty Silo for the reason an empty magazine's does: absence of a bar has to mean "there is
## no Silo there" and not "there is a Silo there with nothing in it".
const CHARGE_FULL: Color = Color(0.58, 0.78, 1.0)
const CHARGE_LOADED: Color = Color(1.0, 0.78, 0.35)
const CHARGE_BACKING: Color = Color(0.09, 0.11, 0.16)
const CHARGE_EMPTY: Color = Color(0.45, 0.07, 0.07)

## Below this fraction of a full magazine the gauge goes amber. Half, because a Turret's
## input buffer is `machine.input_buffer_crafts` crafts deep and half of that is the point
## at which a player still has time to go and look at the Belt.
const AMMUNITION_LOW_FRACTION: float = 0.5

## One node per Machine, pooled: a Machine arriving takes the next free instance and a
## Machine demolished hands one back, so a Factory of fifty costs fifty nodes rather than
## fifty rebuilt every frame.
var _machine_meshes: Array[MeshInstance3D] = []

## What each pooled Machine instance is currently wearing — the path of the body it drew,
## or `box <x>x<z>` where it fell back. Compared against what the Simulation now reports
## so a Machine is re-dressed only when it stops matching, which for a standing Factory
## is never. **Not a mirror of Simulation state**: it describes this node's own meshes,
## and nothing reads it to decide anything about the Run.
var _machine_dressing: PackedStringArray = PackedStringArray()

var _node_meshes: Array[MeshInstance3D] = []

## Every tile of Belt, as instances of one mesh.
##
## A Belt run reaches hundreds of tiles and a tile of trestle is a dozen surfaces, so this
## is one MultiMesh for every Belt on the Map rather than a node each — the same decision
## the Items riding on top of it are drawn with, for the same reason.
var _wall_meshes: MultiMeshInstance3D = null

## The instance transforms handed to the Wall MultiMesh, in the same flat twelve-floats
## layout the Belt buffer uses.
var _wall_transforms: PackedFloat32Array = PackedFloat32Array()

var _belt_meshes: MultiMeshInstance3D = null

## The instance transforms handed to the Belt MultiMesh, in the flat twelve-floats layout
## the Items use, with a yaw in the basis because a tile of Belt points somewhere.
var _belt_transforms: PackedFloat32Array = PackedFloat32Array()

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

## Every Siege Hulk on the Map: its hull, and the vent on its back.
##
## Two MultiMeshes rather than one, and still **never a node per Enemy** — a Hulk is an entry in
## the same Enemy arrays as a Crawler (ADR 0001), so it is drawn the same way. It needs its own
## buffers only because it needs its own *mesh*: a boss drawn with the Crawler's body at the
## Crawler's size would be unreadable, and the vent has to be a second material for the weak
## point to be visible at all. Two fixed nodes however many Hulks arrive.
var _hulk_meshes: MultiMeshInstance3D = null
var _hulk_vent_meshes: MultiMeshInstance3D = null
var _hulk_transforms: PackedFloat32Array = PackedFloat32Array()
var _hulk_vent_transforms: PackedFloat32Array = PackedFloat32Array()

## Every Hive on the Map, as instances of one mesh. One node however many Hives a Map carries,
## for the reason the swarm is one node.
var _hive_meshes: MultiMeshInstance3D = null
var _hive_transforms: PackedFloat32Array = PackedFloat32Array()

## A marker on the ground per shell in the air. A pool rather than a MultiMesh because the
## marker is scaled to the blast radius, which is hot-reloadable tuning, and because there are
## only ever as many of these as there are Siege Hulks.
var _shell_meshes: Array[MeshInstance3D] = []

## The Nest, and a slab per Breach. One node each and not a pool, because there is one
## Nest and the Breaches are fixed geography.
var _nest_mesh: Node3D = null
var _breach_meshes: Array[MeshInstance3D] = []

## A marker per Breach that has been announced but has not opened. A pool, because how many
## are coming is a function of how greedily a player has been digging.
var _pending_breach_meshes: Array[MeshInstance3D] = []

## The Ammunition gauge over every Turret: a dark backing bar and the coloured fill in front
## of it, one pair per Turret. Pools rather than children of a Machine node, because a
## Machine is not a node here either — it is a box this view rebuilds from the queries.
var _turret_gauge_backings: Array[MeshInstance3D] = []
var _turret_gauge_fills: Array[MeshInstance3D] = []

## The Charge gauge over every Silo. The same two meshes and the same argument: mid-Wave a
## player deciding whether to run for the Silo needs to know whether there is artillery in it,
## and they are thirty metres away looking at the whole Factory. A **different colour** from a
## magazine, because the two readings mean different things and a player must not have to
## remember which bar is which.
var _silo_gauge_backings: Array[MeshInstance3D] = []
var _silo_gauge_fills: Array[MeshInstance3D] = []

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

## The generated bodies, merged and cached by id, with `null` recorded for a body the
## pipeline has not produced. One Mesh per *kind* of Machine and not one per Machine:
## fifty Smelters are fifty transforms against one buffer, and a body is read off the
## disk once per Run however many of it get built.
var _bodies: Dictionary = {}

## The hologram the Build Gun projects: the body of the Machine that would land, drawn
## translucent, moved and recoloured every frame from the aim and the refusal the
## Simulation reports — never from a remembered placement. `_hologram_dressing` is the
## same re-dressing bookkeeping the Machines use, so switching the Build Gun's selection
## rebuilds nothing until the selection actually changes.
var _hologram: MeshInstance3D = null
var _hologram_dressing: String = ""

## The scenery: a lit sky and a ground plane with the 2 m grid on it. Not a mirror of
## anything, and the reason scale reads at all — a 1.8 m eye height against 2 m tiles
## means nothing without a surface to see the tiles on.
var _ground: MeshInstance3D = null
var _sun: DirectionalLight3D = null
var _fill: DirectionalLight3D = null
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

## How many Machines the HUD will name before it starts counting them instead. A line a
## Machine is readable at four and is a wall of text over the Factory at fifty, so the
## list is the ones in trouble and the rest are a number — which is also the order a
## player wants them in.
const MACHINES_LISTED: int = 5

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
	_sync_pending_breaches(sim)
	_sync_machines(sim)
	_sync_turret_gauges(sim)
	_sync_silo_gauges(sim)
	_sync_enemies(sim)
	_sync_siege_hulks(sim)
	_sync_hives(sim)
	_sync_shell_markers(sim)
	_sync_belts(sim)
	_sync_walls(sim)
	_sync_items(sim)
	_sync_hologram(sim)
	_sync_hud(sim)
	_place_camera(sim)
	# After the camera, because the weapon hangs off it.
	_sync_weapon(sim)


## How many placeholders are on screen — Nodes plus Machines.
func placeholder_count() -> int:
	return _node_meshes.size() + _machine_meshes.size()


## How many Walls are on screen. Instances of one mesh, so this is a count of transforms:
## there is one node for every Wall on the Map, for the reason there is one for every Belt
## tile. A ring of Walls around a Breach is forty of them and a late-game maze is hundreds.
func wall_instance_count() -> int:
	@warning_ignore("integer_division")
	return _wall_transforms.size() / FLOATS_PER_INSTANCE


## Where a Wall instance is standing, in metres. For the smoke test.
func wall_instance_position(instance: int) -> Vector3:
	return _instance_position(_wall_transforms, instance)


## How many tiles of Belt are on screen. Instances of one mesh, so this is a count of
## transforms — there is one node for every Belt on the Map.
func belt_placeholder_count() -> int:
	@warning_ignore("integer_division")
	return _belt_transforms.size() / FLOATS_PER_INSTANCE


## Where the Nest is standing, in metres. For the smoke test.
func nest_position() -> Vector3:
	if _nest_mesh == null:
		return Vector3.ZERO
	return _nest_mesh.position


## How many Breaches are marked on screen.
func breach_marker_count() -> int:
	return _breach_meshes.size()


## How many Breaches that have not opened yet are marked on screen.
func pending_breach_marker_count() -> int:
	return _pending_breach_meshes.size()


## How many Enemies are on screen. Instances of one mesh, so this is a count of
## transforms rather than a count of nodes — there is one node for the whole swarm.
func enemy_instance_count() -> int:
	@warning_ignore("integer_division")
	return _enemy_transforms.size() / FLOATS_PER_INSTANCE


## How many Siege Hulks and Hives are on screen, as instances rather than nodes. For the smoke
## test that asserts the scene tree does not grow by one node for any of them.
func siege_hulk_instance_count() -> int:
	@warning_ignore("integer_division")
	return _hulk_transforms.size() / FLOATS_PER_INSTANCE


func hive_instance_count() -> int:
	@warning_ignore("integer_division")
	return _hive_transforms.size() / FLOATS_PER_INSTANCE


## How many shell impact markers are on the ground.
func shell_marker_count() -> int:
	return _shell_meshes.size()


## Where a Siege Hulk instance is standing, and where a shell's marker is, in metres. For the
## smoke tests — a MultiMesh keeps its buffer on the rendering server, so the copy this side is
## the only readable record of what was drawn.
func siege_hulk_instance_position(instance: int) -> Vector3:
	return _instance_position(_hulk_transforms, instance)


func shell_marker_position(index: int) -> Vector3:
	if index < 0 or index >= _shell_meshes.size():
		return Vector3.ZERO
	return _shell_meshes[index].position


## Where an Enemy instance is standing, in metres. For the smoke test.
func enemy_instance_position(instance: int) -> Vector3:
	return _instance_position(_enemy_transforms, instance)


## How many Items are on screen.
func item_instance_count() -> int:
	@warning_ignore("integer_division")
	return _item_transforms.size() / FLOATS_PER_INSTANCE


## Where an Item instance is standing, in metres. For the smoke test, and for anything
## later that needs to point at a specific Item.
func item_instance_position(instance: int) -> Vector3:
	return _instance_position(_item_transforms, instance)


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


## How many Charge gauges are on screen. One per Silo and none for anything else.
func silo_gauge_count() -> int:
	return _silo_gauge_fills.size()


## How wide a Silo's Charge gauge is drawn, in metres, and what colour its backing is reading.
## For the smoke test, and for the same reason the Turret's pair exists.
func silo_gauge_width_metres(slot: int) -> float:
	if slot < 0 or slot >= _silo_gauge_fills.size():
		return 0.0
	if not _silo_gauge_fills[slot].visible:
		return 0.0
	return (_silo_gauge_fills[slot].mesh as BoxMesh).size.x


func silo_gauge_backing_colour(slot: int) -> Color:
	if slot < 0 or slot >= _silo_gauge_backings.size():
		return Color.BLACK
	return (_silo_gauge_backings[slot].material_override as StandardMaterial3D).albedo_color


## What colour a Silo's gauge is *filling* in. The fill rather than the backing, because the
## reading that matters about a Silo is whether the Charges in it are still spendable: a loaded
## tube is already committed, and that is a different state from a full stockpile.
func silo_gauge_fill_colour(slot: int) -> Color:
	if slot < 0 or slot >= _silo_gauge_fills.size():
		return Color.BLACK
	return (_silo_gauge_fills[slot].material_override as StandardMaterial3D).albedo_color


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


## Which body a Machine drew, as a `res://` path, or `""` where it fell back to a
## placeholder. For the tests, and for anything later that needs to know whether a
## Machine has art yet.
func machine_body_path(index: int) -> String:
	if index < 0 or index >= _machine_dressing.size():
		return ""
	var dressing: String = _machine_dressing[index]
	return dressing if dressing.begins_with("res://") else ""


## Which way a Machine's body is turned, in radians about Y.
func machine_body_yaw(index: int) -> float:
	if index < 0 or index >= _machine_meshes.size():
		return 0.0
	return _machine_meshes[index].rotation.y


## Where a tile of Belt is drawn, in metres. Instances of one mesh, so this reads a
## transform rather than a node — there is one node for every Belt on the Map.
func belt_instance_position(instance: int) -> Vector3:
	return _instance_position(_belt_transforms, instance)


## Which way a tile of Belt runs, in radians about Y, as it was drawn.
func belt_instance_yaw(instance: int) -> float:
	if instance < 0 or instance >= belt_placeholder_count():
		return 0.0
	var base: int = instance * FLOATS_PER_INSTANCE
	# The basis is row-major in the buffer, so row 2 column 2 is cos(yaw) and row 0
	# column 2 is sin(yaw) — which is the pair atan2 wants, in that order.
	return atan2(_belt_transforms[base + 2], _belt_transforms[base + 10])


# ── The generated bodies ──────────────────────────────────────────────────────
# `tools/assets/generate_machines.sh` produces one `.glb` per body, split into a mesh per
# material so the glTF can name a shared material without embedding its textures. Godot
# imports that as a scene of a dozen `MeshInstance3D`s, which is the wrong shape to draw
# fifty of: it is a dozen nodes and a dozen draw calls per Machine, and it cannot go in a
# MultiMesh at all. So each body is flattened once, on first use, into a single Mesh with
# one surface per material — the same geometry, the same shared materials, one node.

## The body for an id, merged and cached, or `null` when the pipeline has not produced
## one. A miss is cached too, so a Machine with no art costs one `ResourceLoader.exists`
## for the whole Run rather than one a frame.
func _body(id: String) -> Mesh:
	if _bodies.has(id):
		return _bodies[id]
	var merged: Mesh = _merged_body(BODY_DIRECTORY + id + ".glb")
	_bodies[id] = merged
	return merged


## Flattens a generated body into one Mesh, keeping a surface per material.
##
## Returns `null` rather than complaining when there is no such body: a Machine whose art
## has not been drawn yet is an ordinary state for this project to be in — the renderer
## draws a box and says nothing, so adding a row to `content/machines.csv` is never
## blocked on the asset pipeline.
func _merged_body(path: String) -> Mesh:
	if not ResourceLoader.exists(path):
		return null
	var scene: PackedScene = load(path)
	if scene == null:
		return null

	var root: Node = scene.instantiate()
	var surfaces: Dictionary = {}
	_collect_surfaces(root, Transform3D.IDENTITY, surfaces)
	# Instantiated outside the tree, so it is freed rather than queued: nothing will come
	# along to process the queue.
	root.free()

	var merged: ArrayMesh = ArrayMesh.new()
	for skin: Variant in surfaces:
		var built: SurfaceTool = surfaces[skin]
		built.index()
		merged = built.commit(merged)
		merged.surface_set_material(merged.get_surface_count() - 1, skin as Material)
	if merged.get_surface_count() == 0:
		return null
	return merged


## Walks a body's scene, gathering every surface into a SurfaceTool per material.
##
## The port markers the generator leaves behind (`Port_<direction>_<id>`) carry no mesh
## and are skipped by that fact alone — they are a Belt-connection fact for a later
## ticket, not geometry.
func _collect_surfaces(node: Node, parent: Transform3D, surfaces: Dictionary) -> void:
	var here: Transform3D = parent
	if node is Node3D:
		here = parent * (node as Node3D).transform

	if node is MeshInstance3D:
		var instance: MeshInstance3D = node
		var mesh: Mesh = instance.mesh
		if mesh != null:
			for surface: int in range(mesh.get_surface_count()):
				var skin: Material = instance.get_surface_override_material(surface)
				if skin == null:
					skin = mesh.surface_get_material(surface)
				if not surfaces.has(skin):
					var fresh: SurfaceTool = SurfaceTool.new()
					fresh.begin(Mesh.PRIMITIVE_TRIANGLES)
					surfaces[skin] = fresh
				(surfaces[skin] as SurfaceTool).append_from(mesh, surface, here)

	for child: Node in node.get_children():
		_collect_surfaces(child, here, surfaces)


## The yaw, in radians, that turns a body modelled running along +z so that it runs along
## a grid direction instead.
##
## `WorldGrid.DIRECTION_STEPS` counts +x, +z, -x, -z, which walks *clockwise* seen from
## above where Godot's positive rotation about Y is counter-clockwise — so the quarter
## turns run the other way, and direction 1 is the one that needs none.
static func _yaw_for_direction(direction: int) -> float:
	return float(1 - direction) * TAU * 0.25


## The yaw a Machine's body is turned by, in radians, for the rotation the Simulation
## holds. One quarter turn a step, in the same sense a Belt's direction turns.
static func _yaw_for_rotation(rotation: int) -> float:
	return -float(rotation) * TAU * 0.25


## Writes one instance transform — a yaw about Y and a position — into a MultiMesh
## buffer. Row-major, which is the layout TRANSFORM_3D expects.
static func _write_instance(
	buffer: PackedFloat32Array, instance: int, where: Vector3, yaw: float
) -> void:
	var base: int = instance * FLOATS_PER_INSTANCE
	var along: float = sin(yaw)
	var across: float = cos(yaw)
	buffer[base + 0] = across
	buffer[base + 1] = 0.0
	buffer[base + 2] = along
	buffer[base + 3] = where.x
	buffer[base + 4] = 0.0
	buffer[base + 5] = 1.0
	buffer[base + 6] = 0.0
	buffer[base + 7] = where.y
	buffer[base + 8] = -along
	buffer[base + 9] = 0.0
	buffer[base + 10] = across
	buffer[base + 11] = where.z


## The position an instance was drawn at, out of a MultiMesh buffer. A MultiMesh keeps its
## own copy on the rendering server where a headless test cannot see it, so the buffer
## this side is the only readable record of what was drawn.
static func _instance_position(buffer: PackedFloat32Array, instance: int) -> Vector3:
	var base: int = instance * FLOATS_PER_INSTANCE
	if instance < 0 or base + FLOATS_PER_INSTANCE > buffer.size():
		return Vector3.ZERO
	return Vector3(buffer[base + 3], buffer[base + 7], buffer[base + 11])


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
	var total: int = sim.query_machine_count()
	_resize_machine_pool(total)

	for index: int in range(total):
		# The footprint comes from content/machines.csv, through the Simulation, and
		# *turned* — `query_machine_footprint` reports the ground the Machine actually
		# covers. The renderer does not get its own copy of those numbers; the generator
		# builds the body against the same file, and two sources would drift apart on the
		# first balance change.
		var footprint: Vector2i = sim.query_machine_footprint(index)
		var rotation: int = sim.query_machine_rotation(index)
		var instance: MeshInstance3D = _machine_meshes[index]

		# A body is modelled unturned, so a placeholder standing in for one is sized
		# unturned too and then turned by the same yaw. `rotated_footprint` is its own
		# inverse, which is what takes the covered ground back to the declared footprint.
		var declared: Vector2i = WorldGrid.rotated_footprint(footprint.x, footprint.y, rotation)
		var height: float = Fixed.to_float(sim.query_machine_height_metres(index))
		var dressing: String = _dressing_for(sim.query_machine_id(index), declared, height)
		if _machine_dressing[index] != dressing:
			_dress(instance, sim.query_machine_id(index), declared, tile_size, height)
			_machine_dressing[index] = dressing

		instance.rotation = Vector3(0.0, _yaw_for_rotation(rotation), 0.0)
		instance.position = _footprint_centre(sim, sim.query_machine_tile(index), footprint)
		# A placeholder box is modelled about its own centre rather than standing on the
		# ground, so it is the one thing that has to be lifted onto its feet.
		if not dressing.begins_with("res://"):
			instance.position.y += height * 0.5


## Grows or shrinks the Machine pool. A node per Machine and not per frame: a standing
## Factory re-dresses nothing, and a demolition hands an instance back rather than
## discarding the whole pool.
func _resize_machine_pool(wanted: int) -> void:
	while _machine_meshes.size() > wanted:
		var spare: MeshInstance3D = _machine_meshes.pop_back()
		_machine_dressing.remove_at(_machine_dressing.size() - 1)
		remove_child(spare)
		spare.queue_free()

	while _machine_meshes.size() < wanted:
		var fresh: MeshInstance3D = MeshInstance3D.new()
		add_child(fresh)
		_machine_meshes.append(fresh)
		_machine_dressing.append("")


## What a Machine of this id and footprint should be wearing: the path of its generated
## body, or a `box` description when there is none. Compared against what an instance is
## already wearing, so re-dressing happens on a change and not on a frame.
func _dressing_for(id: String, footprint: Vector2i, height: float) -> String:
	if _body(id) != null:
		return BODY_DIRECTORY + id + ".glb"
	# The height is part of the description because `height_metres` is hot-reloadable
	# tuning: a Machine that got taller has to be re-dressed, and a footprint alone would
	# not notice.
	return "box %dx%d x %s" % [footprint.x, footprint.y, String.num(height, 3)]


## Puts a body on an instance, or a placeholder box sized to its footprint where there is
## no body. The placeholder is a plain slab-grey, deliberately unlike the generated
## surfaces, so "this Machine has no art yet" reads as a fact rather than as a bug.
func _dress(
	instance: MeshInstance3D, id: String, footprint: Vector2i, tile_size: float, height: float
) -> void:
	var body: Mesh = _body(id)
	if body != null:
		instance.mesh = body
		instance.material_override = null
		return

	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(
		float(footprint.x) * tile_size, height, float(footprint.y) * tile_size
	)
	instance.mesh = box
	var skin: StandardMaterial3D = StandardMaterial3D.new()
	skin.albedo_color = Color(0.35, 0.37, 0.33)
	skin.roughness = 0.85
	instance.material_override = skin


## The centre of the ground a footprint covers, in metres, on the layer it stands on.
## Which is where a generated body's origin goes, because every body is modelled about
## the centre of its footprint with its feet on the ground.
func _footprint_centre(sim: Simulation, tile: Vector3i, footprint: Vector2i) -> Vector3:
	var near: FixedVec2 = sim.query_tile_centre_metres(tile)
	var far: FixedVec2 = sim.query_tile_centre_metres(
		Vector3i(tile.x + footprint.x - 1, tile.y, tile.z + footprint.y - 1)
	)
	return Vector3(
		(Fixed.to_float(near.x) + Fixed.to_float(far.x)) * 0.5,
		Fixed.to_float(sim.query_layer_height_metres(tile.y)),
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
			+ Vector3(0.0, MACHINE_GAUGE_HEIGHT_METRES + AMMUNITION_GAUGE_LIFT_METRES, 0.0)
		)

		_hang_gauge(
			_turret_gauge_backings,
			_turret_gauge_fills,
			slot,
			above,
			fraction,
			AMMUNITION_DRY if held == 0 else AMMUNITION_BACKING,
			AMMUNITION_LOW if fraction < AMMUNITION_LOW_FRACTION else AMMUNITION_FULL,
			held > 0
		)


## A Charge gauge over every Silo, and over nothing else.
##
## `_sync_turret_gauges`' argument, applied to the other number a player triages on. The fill
## goes amber the moment the Silo is **loaded**, because a loaded Silo is a different thing
## from a full one: the Charges in the tube are spent whatever happens next, and that is the
## state a player has to be able to see without walking over and reading a dial.
func _sync_silo_gauges(sim: Simulation) -> void:
	var silos: PackedInt64Array = PackedInt64Array()
	for index: int in range(sim.query_machine_count()):
		if sim.query_machine_is_silo(index):
			silos.append(index)

	_resize_pool(
		_silo_gauge_backings,
		silos.size(),
		AMMUNITION_GAUGE_WIDTH_METRES,
		AMMUNITION_GAUGE_HEIGHT_METRES,
		CHARGE_BACKING
	)
	_resize_pool(
		_silo_gauge_fills,
		silos.size(),
		AMMUNITION_GAUGE_WIDTH_METRES,
		AMMUNITION_GAUGE_HEIGHT_METRES,
		CHARGE_FULL
	)

	for slot: int in range(silos.size()):
		var index: int = silos[slot]
		var loaded: int = sim.query_silo_loaded_charges(index)
		var held: int = sim.query_silo_charges(index) + loaded
		var capacity: int = maxi(sim.query_silo_charge_capacity(index), 1)
		_hang_gauge(
			_silo_gauge_backings,
			_silo_gauge_fills,
			slot,
			_machine_centre(sim, index)
			+ Vector3(0.0, MACHINE_GAUGE_HEIGHT_METRES + AMMUNITION_GAUGE_LIFT_METRES, 0.0),
			clampf(float(held) / float(capacity), 0.0, 1.0),
			CHARGE_EMPTY if held == 0 else CHARGE_BACKING,
			CHARGE_LOADED if loaded > 0 else CHARGE_FULL,
			held > 0
		)


## Hangs one gauge: a dark backing bar at full width and a coloured fill in front of it.
##
## Extracted so the Charge gauge is the Ammunition gauge rather than a second one that looks
## like it. The fill grows **from the left**, so an emptying bar reads as retreating rather
## than as shrinking towards its middle — the same direction every gauge a player has ever
## read empties in — and both meshes are unshaded, because a gauge a directional light can
## darken is a gauge a player misreads at the worst moment.
func _hang_gauge(
	backings: Array[MeshInstance3D],
	fills: Array[MeshInstance3D],
	slot: int,
	above: Vector3,
	fraction: float,
	backing_colour: Color,
	fill_colour: Color,
	fill_visible: bool
) -> void:
	var backing: BoxMesh = backings[slot].mesh
	backing.size = Vector3(
		AMMUNITION_GAUGE_WIDTH_METRES,
		AMMUNITION_GAUGE_HEIGHT_METRES,
		AMMUNITION_GAUGE_DEPTH_METRES
	)
	backings[slot].position = above
	_paint_gauge(backings[slot], backing_colour)

	var width: float = AMMUNITION_GAUGE_WIDTH_METRES * fraction
	var fill: BoxMesh = fills[slot].mesh
	fill.size = Vector3(
		maxf(width, 0.001),
		AMMUNITION_GAUGE_HEIGHT_METRES,
		AMMUNITION_GAUGE_DEPTH_METRES * 1.4
	)
	fills[slot].position = above + Vector3(
		(width - AMMUNITION_GAUGE_WIDTH_METRES) * 0.5, 0.0, 0.0
	)
	fills[slot].visible = fill_visible
	_paint_gauge(fills[slot], fill_colour)


## Colours a gauge bar, unshaded so it reads the same in the Factory's shadow as it does in
## the sun. A gauge that a directional light could darken is a gauge a player misreads at
## the worst moment.
func _paint_gauge(bar: MeshInstance3D, colour: Color) -> void:
	var skin: StandardMaterial3D = bar.material_override
	skin.albedo_color = colour
	skin.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


## The middle of a Machine's footprint at ground level, in metres. The same placement
## `_sync_machines` seats the body with, so a gauge cannot end up over a different Machine.
func _machine_centre(sim: Simulation, index: int) -> Vector3:
	return _footprint_centre(
		sim, sim.query_machine_tile(index), sim.query_machine_footprint(index)
	)


## The Nest: one body, standing on the middle of its footprint.
##
## Built once, because the Nest does not move. Its generated body is loaded when the asset
## pipeline has produced one and a placeholder box stands in otherwise, so the Simulation
## and the tests do not depend on an import having run.
func _sync_nest(sim: Simulation) -> void:
	var tile_size: float = Fixed.to_float(sim.query_tile_size_metres())
	var footprint: Vector2i = sim.query_nest_footprint()

	if _nest_mesh == null:
		_nest_mesh = _nest_body(footprint, tile_size)
		add_child(_nest_mesh)

	_nest_mesh.position = _footprint_centre(sim, sim.query_nest_tile(), footprint)


## The Nest's body: its generated mesh if there is one, and a tall box if there is not.
##
## A holder with the body parented under it, so `_nest_mesh.position` means the floor of
## the footprint either way — a box is modelled about its centre and has to be lifted onto
## its feet, where a generated body already stands on them.
func _nest_body(footprint: Vector2i, tile_size: float) -> Node3D:
	var holder: Node3D = Node3D.new()
	var body: MeshInstance3D = MeshInstance3D.new()
	var mesh: Mesh = _body(NEST_BODY)
	if mesh != null:
		body.mesh = mesh
	else:
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3(
			float(footprint.x) * tile_size, NEST_HEIGHT_METRES, float(footprint.y) * tile_size
		)
		body.mesh = box
		body.position = Vector3(0.0, NEST_HEIGHT_METRES * 0.5, 0.0)
		var skin: StandardMaterial3D = StandardMaterial3D.new()
		skin.albedo_color = Color(0.46, 0.40, 0.30)
		body.material_override = skin
	holder.add_child(body)
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


## A bright frame on the ground wherever a Breach is about to open.
##
## Drawn from `query_pending_breach_*`, which is a projection about a hole that does not exist
## yet — the same arrangement the build hologram has, and for the same reason: the player is
## told before the fact rather than after it. The pool empties itself when the Breach opens,
## because `_sync_breaches` then has one more to draw.
func _sync_pending_breaches(sim: Simulation) -> void:
	var tile_size: float = Fixed.to_float(sim.query_tile_size_metres())
	_resize_pool(
		_pending_breach_meshes,
		sim.query_pending_breach_count(),
		tile_size,
		PENDING_BREACH_HEIGHT_METRES,
		Color(0.90, 0.38, 0.12)
	)
	for index: int in range(sim.query_pending_breach_count()):
		var tile: Vector3i = sim.query_pending_breach_tile(index)
		var centre: FixedVec2 = sim.query_tile_centre_metres(tile)
		_pending_breach_meshes[index].position = Vector3(
			Fixed.to_float(centre.x),
			Fixed.to_float(sim.query_layer_height_metres(tile.y))
			+ PENDING_BREACH_HEIGHT_METRES * 0.5,
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
		instanced.mesh = _crawler_mesh()
		_enemy_meshes.multimesh = instanced
		add_child(_enemy_meshes)

	# The swarm, which is every kind but the boss: a Siege Hulk is four metres of armour and is
	# drawn by `_sync_siege_hulks` through its own mesh. Same arrays, same queries, different
	# silhouette — which is the whole of what "a boss is one more array entry" costs the
	# renderer.
	var total: int = 0
	for index: int in range(sim.query_enemy_count()):
		if sim.query_enemy_kind(index) != Simulation.ENEMY_KIND_SIEGE_HULK:
			total += 1
	_enemy_transforms.resize(total * FLOATS_PER_INSTANCE)
	var instance: int = 0
	for index: int in range(sim.query_enemy_count()):
		if sim.query_enemy_kind(index) == Simulation.ENEMY_KIND_SIEGE_HULK:
			continue
		var where: FixedVec2 = sim.query_enemy_position_metres(index)
		# A Crawler faces the way the flowfield is sending it, which is a query like
		# everything else here — the Simulation decides where it is going and this draws
		# it pointing that way. A Crawler on a tile the field cannot route keeps the
		# heading it had, which is the same thing the Simulation does with it.
		var heading: int = sim.query_flow_direction(sim.query_enemy_tile(index))
		var yaw: float = _yaw_for_direction(heading) if heading >= 0 else 0.0
		_write_instance(
			_enemy_transforms,
			instance,
			Vector3(Fixed.to_float(where.x), 0.0, Fixed.to_float(where.z)),
			yaw
		)
		instance += 1

	_enemy_meshes.multimesh.instance_count = total
	if total > 0:
		_enemy_meshes.multimesh.buffer = _enemy_transforms


## Every Siege Hulk on the Map, hull and vent, turned to face what it is pointed at.
##
## **The yaw comes out of `query_enemy_facing_point_metres` rather than out of a stored angle**,
## because the Simulation holds a *point* — a point reduces the weak-point test to the sign of a
## dot product and needs no arc-tangent in fixed point. The `atan2` is here, on the outbound side
## of the boundary, which is exactly where a float belongs.
##
## The vent is drawn one offset *behind* the hull along that same facing, so the glowing end is
## the end that is not armoured. That is the only place in this project where geometry carries a
## rule: the weak point has to be discoverable by looking at the thing, and a HUD line naming it
## would spend the discovery.
func _sync_siege_hulks(sim: Simulation) -> void:
	if _hulk_meshes == null:
		_hulk_meshes = _instanced(_siege_hulk_hull_mesh())
		_hulk_vent_meshes = _instanced(_siege_hulk_vent_mesh())

	var total: int = 0
	for index: int in range(sim.query_enemy_count()):
		if sim.query_enemy_kind(index) == Simulation.ENEMY_KIND_SIEGE_HULK:
			total += 1
	_hulk_transforms.resize(total * FLOATS_PER_INSTANCE)
	_hulk_vent_transforms.resize(total * FLOATS_PER_INSTANCE)

	var instance: int = 0
	for index: int in range(sim.query_enemy_count()):
		if sim.query_enemy_kind(index) != Simulation.ENEMY_KIND_SIEGE_HULK:
			continue
		var where: FixedVec2 = sim.query_enemy_position_metres(index)
		var at: Vector3 = Vector3(Fixed.to_float(where.x), 0.0, Fixed.to_float(where.z))
		var facing: FixedVec2 = sim.query_enemy_facing_point_metres(index)
		var nose_x: float = Fixed.to_float(facing.x) - at.x
		var nose_z: float = Fixed.to_float(facing.z) - at.z
		var length: float = sqrt(nose_x * nose_x + nose_z * nose_z)
		# `_write_instance` maps local +z to (sin yaw, cos yaw), and every mesh in this file is
		# modelled nose along +z, so the yaw that points the nose at a place is atan2 of the gap.
		var yaw: float = 0.0
		if length > 0.0:
			yaw = atan2(nose_x / length, nose_z / length)
		_write_instance(_hulk_transforms, instance, at, yaw)
		var behind: float = SIEGE_HULK_SIZE_METRES * 0.42
		_write_instance(
			_hulk_vent_transforms,
			instance,
			at - Vector3(sin(yaw), 0.0, cos(yaw)) * behind,
			yaw
		)
		instance += 1

	_hulk_meshes.multimesh.instance_count = total
	_hulk_vent_meshes.multimesh.instance_count = total
	if total > 0:
		_hulk_meshes.multimesh.buffer = _hulk_transforms
		_hulk_vent_meshes.multimesh.buffer = _hulk_vent_transforms


## Every Hive on the Map. One instance each through one MultiMesh, and the count falls for good
## when one is destroyed — there is nothing in the Simulation that puts one back.
func _sync_hives(sim: Simulation) -> void:
	if _hive_meshes == null:
		_hive_meshes = _instanced(_hive_mesh())

	var total: int = sim.query_hive_count()
	_hive_transforms.resize(total * FLOATS_PER_INSTANCE)
	for index: int in range(total):
		var centre: FixedVec2 = sim.query_tile_centre_metres(sim.query_hive_tile(index))
		_write_instance(
			_hive_transforms,
			index,
			Vector3(Fixed.to_float(centre.x), 0.0, Fixed.to_float(centre.z)),
			0.0
		)
	_hive_meshes.multimesh.instance_count = total
	if total > 0:
		_hive_meshes.multimesh.buffer = _hive_transforms


## A ring of ground wherever a shell is about to land, brightening as it comes down.
##
## Drawn from `query_shell_impact_metres` and `query_shell_blast_radius_metres`, so the marker is
## the blast rather than a guess at it, and from `query_shell_ticks_remaining`, so the brightening
## is the Simulation's own countdown rather than an animation this node invented.
func _sync_shell_markers(sim: Simulation) -> void:
	var diameter: float = Fixed.to_float(sim.query_shell_blast_radius_metres()) * 2.0
	_resize_pool(
		_shell_meshes,
		sim.query_shell_count(),
		diameter,
		SHELL_MARKER_HEIGHT_METRES,
		SHELL_MARKER_FAR
	)
	var flight: float = maxf(float(sim.query_shell_flight_ticks()), 1.0)
	for index: int in range(sim.query_shell_count()):
		var at: FixedVec2 = sim.query_shell_impact_metres(index)
		var marker: MeshInstance3D = _shell_meshes[index]
		# Re-sized every frame rather than at creation, because the blast radius is tuning and
		# tuning is hot-reloadable: a marker that kept the size it was born with would be lying
		# about the shell the moment somebody edited the file.
		var box: BoxMesh = marker.mesh
		box.size = Vector3(diameter, SHELL_MARKER_HEIGHT_METRES, diameter)
		marker.position = Vector3(
			Fixed.to_float(at.x), SHELL_MARKER_HEIGHT_METRES * 0.5, Fixed.to_float(at.z)
		)
		var closing: float = clampf(
			1.0 - float(sim.query_shell_ticks_remaining(index)) / flight, 0.0, 1.0
		)
		var material: StandardMaterial3D = marker.material_override
		material.albedo_color = SHELL_MARKER_FAR.lerp(SHELL_MARKER_NEAR, closing)


## A `MultiMeshInstance3D` holding one mesh, added to the tree. The two lines every instanced
## thing in this file needs, in one place.
func _instanced(mesh: Mesh) -> MultiMeshInstance3D:
	var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
	var instanced: MultiMesh = MultiMesh.new()
	instanced.transform_format = MultiMesh.TRANSFORM_3D
	instanced.mesh = mesh
	node.multimesh = instanced
	add_child(node)
	return node


## One Siege Hulk's hull: a wide armoured sled on four legs with a mortar tube over it, nose
## along +z. Cast iron, and deliberately featureless at the front — the front is the end that
## does not reward being shot at.
func _siege_hulk_hull_mesh() -> Mesh:
	var built: SurfaceTool = SurfaceTool.new()
	built.begin(Mesh.PRIMITIVE_TRIANGLES)
	var size: float = SIEGE_HULK_SIZE_METRES
	var block: BoxMesh = BoxMesh.new()
	block.size = Vector3.ONE

	# The hull: low, wide and long, which is what makes it read as a siege engine rather than a
	# big Crawler.
	built.append_from(block, 0, Transform3D(
		Basis.from_scale(Vector3(size * 0.70, size * 0.40, size * 0.95)),
		Vector3(0.0, size * 0.42, 0.0)
	))
	# The glacis: a sloped plate across the front, which is the armour the player is going to
	# waste a magazine on.
	built.append_from(block, 0, Transform3D(
		Basis.from_scale(Vector3(size * 0.74, size * 0.30, size * 0.18)),
		Vector3(0.0, size * 0.30, size * 0.50)
	))
	# The mortar, raised and pointed forward, so what it is aimed at is readable from the side.
	built.append_from(block, 0, Transform3D(
		Basis.from_scale(Vector3(size * 0.22, size * 0.22, size * 0.80)),
		Vector3(0.0, size * 0.74, size * 0.10)
	))
	# Four legs, outside the hull, so the outline has a gait.
	for side: int in [-1, 1]:
		for pair: int in [-1, 1]:
			built.append_from(block, 0, Transform3D(
				Basis.from_scale(Vector3(size * 0.14, size * 0.44, size * 0.14)),
				Vector3(float(side) * size * 0.42, size * 0.22, float(pair) * size * 0.34)
			))

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = SIEGE_HULK_HULL
	material.metallic = 0.8
	material.roughness = 0.55
	built.set_material(material)
	return built.commit()


## The vent on a Siege Hulk's back: a glowing block, drawn behind the hull along its own facing.
## Unshaded, for the reason a Turret's gauge is: a weak point a directional light can darken is a
## weak point a player misreads at the worst moment.
func _siege_hulk_vent_mesh() -> Mesh:
	var built: SurfaceTool = SurfaceTool.new()
	built.begin(Mesh.PRIMITIVE_TRIANGLES)
	var size: float = SIEGE_HULK_SIZE_METRES
	var block: BoxMesh = BoxMesh.new()
	block.size = Vector3.ONE
	built.append_from(block, 0, Transform3D(
		Basis.from_scale(Vector3(size * 0.46, size * 0.34, size * 0.16)),
		Vector3(0.0, size * 0.50, 0.0)
	))
	for side: int in [-1, 1]:
		built.append_from(block, 0, Transform3D(
			Basis.from_scale(Vector3(size * 0.10, size * 0.44, size * 0.12)),
			Vector3(float(side) * size * 0.30, size * 0.56, 0.0)
		))

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = SIEGE_HULK_VENT
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	built.set_material(material)
	return built.commit()


## One Hive: a mound of stacked chambers narrowing upward, with a mouth at the front. Grown
## rather than welded, which is what keeps it from reading as something the players built.
func _hive_mesh() -> Mesh:
	var built: SurfaceTool = SurfaceTool.new()
	built.begin(Mesh.PRIMITIVE_TRIANGLES)
	var size: float = HIVE_SIZE_METRES
	var block: BoxMesh = BoxMesh.new()
	block.size = Vector3.ONE

	var tiers: int = 4
	for tier: int in range(tiers):
		var shrink: float = 1.0 - float(tier) * 0.22
		built.append_from(block, 0, Transform3D(
			Basis.from_scale(Vector3(size * 0.90 * shrink, size * 0.30, size * 0.90 * shrink)),
			Vector3(0.0, size * (0.15 + float(tier) * 0.26), 0.0)
		))
	# The mouth, jutting out at the front, so a Hive has an end a player can stand in front of.
	built.append_from(block, 0, Transform3D(
		Basis.from_scale(Vector3(size * 0.34, size * 0.34, size * 0.40)),
		Vector3(0.0, size * 0.22, size * 0.52)
	))

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = HIVE_COLOUR
	material.roughness = 0.9
	built.set_material(material)
	return built.commit()


## One Crawler: a low armoured carapace on six legs, nose along +z.
##
## Built here rather than generated, because it is the one mesh in the game that has to go
## in a MultiMesh — a thousand of these are a thousand transforms against one buffer, so
## it is a handful of boxes and stays a handful of boxes. Shape over detail: at twenty
## metres what reads is "low, wide, many-legged, coming at you", and nothing else survives
## the distance.
func _crawler_mesh() -> Mesh:
	var built: SurfaceTool = SurfaceTool.new()
	built.begin(Mesh.PRIMITIVE_TRIANGLES)
	var size: float = ENEMY_SIZE_METRES

	var block: BoxMesh = BoxMesh.new()
	block.size = Vector3.ONE

	# The abdomen, the thorax it tapers into and the head jutting ahead of both: three
	# blocks of falling height, which is what makes the silhouette read as *pointed*
	# rather than as a brick.
	built.append_from(block, 0, Transform3D(
		Basis.from_scale(Vector3(size * 0.78, size * 0.46, size * 0.62)),
		Vector3(0.0, size * 0.40, -size * 0.30)
	))
	built.append_from(block, 0, Transform3D(
		Basis.from_scale(Vector3(size * 0.62, size * 0.34, size * 0.50)),
		Vector3(0.0, size * 0.36, size * 0.18)
	))
	built.append_from(block, 0, Transform3D(
		Basis.from_scale(Vector3(size * 0.34, size * 0.22, size * 0.34)),
		Vector3(0.0, size * 0.26, size * 0.54)
	))
	# Mandibles, so the front end is the end that bites.
	for side: int in [-1, 1]:
		built.append_from(block, 0, Transform3D(
			Basis.from_scale(Vector3(size * 0.09, size * 0.09, size * 0.30)),
			Vector3(float(side) * size * 0.14, size * 0.20, size * 0.78)
		))

	# Six legs, splayed and stepping outside the body, which is the whole reason this is
	# not a box: a bug's outline is the legs.
	for side: int in [-1, 1]:
		for pair: int in range(3):
			var along: float = (float(pair) - 1.0) * size * 0.34
			built.append_from(block, 0, Transform3D(
				Basis.from_scale(Vector3(size * 0.42, size * 0.08, size * 0.10)),
				Vector3(float(side) * size * 0.52, size * 0.30, along)
			))
			built.append_from(block, 0, Transform3D(
				Basis.from_scale(Vector3(size * 0.09, size * 0.30, size * 0.09)),
				Vector3(float(side) * size * 0.70, size * 0.15, along)
			))

	built.index()
	var merged: ArrayMesh = built.commit()
	# Chitin: dark, dull and faintly warm, so a swarm reads against the ochre ground
	# without glowing like a hazard marker.
	var skin: StandardMaterial3D = StandardMaterial3D.new()
	skin.albedo_color = Color(0.21, 0.07, 0.06)
	skin.metallic = 0.25
	skin.roughness = 0.55
	merged.surface_set_material(0, skin)
	return merged


## Every tile of Belt on the Map, turned to the direction its run goes in.
##
## One MultiMesh for the lot. A tile of trestle is a dozen surfaces and a Belt run reaches
## hundreds of tiles, so a node a tile would be thousands of nodes for the system the
## project's performance budget is written around — the Items riding on top of it are
## instanced for the same reason, and this is the same decision one level down.
func _sync_belts(sim: Simulation) -> void:
	var tile_size: float = Fixed.to_float(sim.query_tile_size_metres())
	if _belt_meshes == null:
		_belt_meshes = MultiMeshInstance3D.new()
		var instanced: MultiMesh = MultiMesh.new()
		instanced.transform_format = MultiMesh.TRANSFORM_3D
		var body: Mesh = _body(BELT_BODY)
		if body != null:
			instanced.mesh = body
		else:
			# No Belt art yet: a low slab, flat on the ground, so the Items on top of it
			# are still what the eye follows along a line.
			var slab: BoxMesh = BoxMesh.new()
			slab.size = Vector3(tile_size, BELT_HEIGHT_METRES, tile_size)
			instanced.mesh = slab
			var skin: StandardMaterial3D = StandardMaterial3D.new()
			skin.albedo_color = Color(0.24, 0.22, 0.20)
			_belt_meshes.material_override = skin
		_belt_meshes.multimesh = instanced
		add_child(_belt_meshes)

	# A placeholder slab is modelled about its own centre, so it alone has to be lifted
	# onto its feet; a generated tile of trestle already stands on the ground.
	var lift: float = 0.0 if _body(BELT_BODY) != null else BELT_HEIGHT_METRES * 0.5

	var tiles: int = 0
	for index: int in range(sim.query_belt_count()):
		tiles += sim.query_belt_length_tiles(index)
	_belt_transforms.resize(tiles * FLOATS_PER_INSTANCE)

	var instance: int = 0
	for index: int in range(sim.query_belt_count()):
		# A Belt run is a straight line of tiles, so the queries are asked where it starts
		# and which way it goes and the rest of the run is walked from there — one tile
		# step a tile, out of `WorldGrid.direction_step`, which is the one place the
		# meaning of a direction is written down. Asking `query_belt_tile` and
		# `query_tile_centre_metres` per tile instead costs about five times as much, and
		# a Belt run reaches hundreds of tiles.
		var direction: int = sim.query_belt_direction(index)
		var yaw: float = _yaw_for_direction(direction)
		var step: Vector3i = WorldGrid.direction_step(direction)
		var anchor: Vector3i = sim.query_belt_tile(index, 0)
		var centre: FixedVec2 = sim.query_tile_centre_metres(anchor)
		var at: Vector3 = Vector3(
			Fixed.to_float(centre.x),
			Fixed.to_float(sim.query_layer_height_metres(anchor.y)) + lift,
			Fixed.to_float(centre.z)
		)
		var along: Vector3 = Vector3(float(step.x), 0.0, float(step.z)) * tile_size
		for tile: int in range(sim.query_belt_length_tiles(index)):
			_write_instance(_belt_transforms, instance, at, yaw)
			at += along
			instance += 1

	_belt_meshes.multimesh.instance_count = tiles
	if tiles > 0:
		_belt_meshes.multimesh.buffer = _belt_transforms


## Every Wall on the Map, as one block a tile.
##
## **One MultiMesh and never a node each**, the decision a Belt tile already made and for the
## same arithmetic: a Wall is the cheapest thing in the game to build, so a player who has
## decided where a Wave walks has built hundreds of them, and a node apiece would put the
## count a Factory's own Machines were spared straight back on the scene tree.
##
## Drawn at full size whatever its health. A Wall is either standing or it is gone — there is
## no rubble (see `Simulation._destroy_machine`) — so shrinking a damaged one would say
## something false about what an Enemy has to chew through. The damage shows in the colour
## instead, which is readable from the thirty metres a player triages a Wave from.
func _sync_walls(sim: Simulation) -> void:
	var tile_size: float = Fixed.to_float(sim.query_tile_size_metres())
	# **How tall a Wall is comes from the Simulation**, because a Wall has no generated body:
	# the box *is* the Wall, so a constant here would be a second authority on the one thing
	# a player can walk into. `wall.height_metres` is also hot-reloadable, which is why the
	# size is written every sync rather than once with the mesh.
	var wall_height: float = Fixed.to_float(sim.query_wall_height_metres())
	if _wall_meshes == null:
		_wall_meshes = MultiMeshInstance3D.new()
		var instanced: MultiMesh = MultiMesh.new()
		instanced.transform_format = MultiMesh.TRANSFORM_3D
		# Per-instance colour, because the whole point of drawing Walls is reading which one
		# is being chewed. A MultiMesh carries that without a node or a material each.
		instanced.use_colors = true
		instanced.mesh = BoxMesh.new()
		var skin: StandardMaterial3D = StandardMaterial3D.new()
		skin.vertex_color_use_as_albedo = true
		skin.roughness = 0.85
		_wall_meshes.material_override = skin
		_wall_meshes.multimesh = instanced
		add_child(_wall_meshes)

	(_wall_meshes.multimesh.mesh as BoxMesh).size = Vector3(
		tile_size * WALL_WIDTH_FRACTION, wall_height, tile_size * WALL_WIDTH_FRACTION
	)

	var walls: int = sim.query_wall_count()
	_wall_transforms.resize(walls * FLOATS_PER_INSTANCE)
	_wall_meshes.multimesh.instance_count = walls

	var whole: int = maxi(sim.query_wall_max_health(), 1)
	for index: int in range(walls):
		var tile: Vector3i = sim.query_wall_tile(index)
		var centre: FixedVec2 = sim.query_tile_centre_metres(tile)
		# Modelled about its own centre, so it is lifted onto its feet like the Belt slab.
		_write_instance(
			_wall_transforms,
			index,
			Vector3(
				Fixed.to_float(centre.x),
				Fixed.to_float(sim.query_layer_height_metres(tile.y)) + wall_height * 0.5,
				Fixed.to_float(centre.z)
			),
			0.0
		)
		_wall_meshes.multimesh.set_instance_color(
			index,
			WALL_RUINED.lerp(
				WALL_WHOLE, clampf(float(sim.query_wall_health(index)) / float(whole), 0.0, 1.0)
			)
		)
	if walls > 0:
		_wall_meshes.multimesh.buffer = _wall_transforms


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

	var deck: float = BELT_DECK_METRES if _body(BELT_BODY) != null else BELT_HEIGHT_METRES
	_item_transforms.resize(total * FLOATS_PER_INSTANCE)
	var instance: int = 0
	for index: int in range(sim.query_belt_count()):
		var layer: int = sim.query_belt_tile(index, 0).y
		var height: float = (
			Fixed.to_float(sim.query_layer_height_metres(layer)) + deck + ITEM_SIZE_METRES * 0.5
		)
		for slot: int in range(sim.query_belt_item_count(index)):
			var where: FixedVec2 = sim.query_belt_item_position_metres(index, slot)
			_write_instance(
				_item_transforms,
				instance,
				Vector3(Fixed.to_float(where.x), height, Fixed.to_float(where.z)),
				0.0
			)
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
	lines.append_array(_breach_opening_lines(sim))
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
	lines.append_array(_siege_hulk_lines(sim))
	lines.append_array(_sortie_lines(sim))
	lines.append_array(_delivery_lines(sim))
	lines.append_array(_nest_store_lines(sim))
	lines.append_array(_gear_lines(sim))
	lines.append_array(_silo_lines(sim))
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

	# Machines in trouble first, then the hottest, and only as many as a player can read.
	# A line per Machine buries a real Factory under its own diagnostics — fifty lines of
	# "running" tell nobody anything, and they are drawn over the Factory they describe.
	#
	# A healthy Machine still earns its line when it is one of the hottest, because Heat
	# is a bet a player can only make knowingly if they can see what is making them hot,
	# and the Machines making the most Heat are usually the ones in no trouble at all.
	var hottest: Array[int] = []
	for index: int in range(sim.query_machine_count()):
		hottest.append(index)
	hottest.sort_custom(
		func(a: int, b: int) -> bool:
			var rate_a: int = sim.query_machine_heat_per_minute(a)
			var rate_b: int = sim.query_machine_heat_per_minute(b)
			if rate_a != rate_b:
				return rate_a > rate_b
			return a < b
	)
	var is_hot: Dictionary = {}
	for rank: int in range(mini(MACHINES_LISTED, hottest.size())):
		var candidate: int = hottest[rank]
		if sim.query_machine_heat_per_minute(candidate) > 0:
			is_hot[candidate] = true

	var healthy: int = 0
	var listed: int = 0
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
		# Damage outranks both, because it is the only one of the three that ends with the
		# Machine gone. A starved Smelter is a logistics problem and a chewed one is a
		# countdown, so a player triaging a Wave has to be able to tell them apart at a
		# glance — and the fix is a different tool, not a different Belt.
		var hurt: bool = sim.query_machine_health(index) < sim.query_machine_max_health(index)
		if hurt:
			state = "DAMAGED"
		# A Turret is always named, however healthy it looks: "running" and out of
		# Ammunition are the same word for a Turret, and a dry one costs the Run.
		# A Miner running up a Breach is always named too, for exactly the reason a Turret is:
		# "running" is the wrong word for a Machine whose consequence a player has not seen
		# yet, and a consequence nobody watched themselves cause reads as bad luck.
		if (
			state == "running"
			and not hurt
			and not sim.query_machine_is_turret(index)
			and not sim.query_machine_is_silo(index)
			and not _is_digging_up_a_breach(sim, index)
			and not is_hot.has(index)
		):
			healthy += 1
			continue
		if listed >= MACHINES_LISTED:
			continue
		listed += 1
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
		# How close this mine is to opening a Breach, on the mine's own line. The Heat rule
		# applied to geography: a player reads the cause next to the thing causing it.
		if _is_digging_up_a_breach(sim, index):
			var node: int = sim.query_node_under_machine(index)
			line += " — digging %d/%d" % [
				sim.query_node_deep_crafts(node),
				sim.query_node_deep_crafts_until_a_breach(),
			]
		if sim.query_machine_is_turret(index):
			var held: int = sim.query_turret_ammunition(index)
			var what: String = (
				"plate" if sim.query_machine_is_repair_pylon(index) else "ammo"
			)
			line += " — %s %d/%d" % [what, held, sim.query_turret_ammunition_capacity(index)]
			if sim.query_machine_is_repair_pylon(index):
				line += " — DRY" if held == 0 else " — mending"
			else:
				line += (
					" — DRY" if held == 0
					else " — %d shots" % sim.query_turret_shots_remaining(index)
				)
		# A Silo's stockpile and what is in its tube, on the Silo's own line. The Turret rule
		# applied to the heaviest weapon in the game: "running" says nothing about whether
		# there is artillery to call, and a load is irreversible, so what is committed is
		# worth reading in words as well as off the gauge over its roof.
		if sim.query_machine_is_silo(index):
			line += " — charges %d/%d" % [
				sim.query_silo_charges(index), sim.query_silo_charge_capacity(index)
			]
			if sim.query_silo_is_loaded(index):
				line += " — LOADED %s x%d" % [
					sim.query_silo_loaded_stratagem(index),
					sim.query_silo_loaded_charges(index),
				]
			else:
				line += " — empty tube"
		# How long a dropped Sentry has left to live. A Turret a player did not build and
		# cannot repair back into permanence is a Turret whose clock is the only thing worth
		# knowing about it.
		if sim.query_machine_is_temporary(index):
			line += " — %ds left" % (
				sim.query_machine_ticks_remaining(index) / Simulation.TICKS_PER_SECOND
			)
		if hurt:
			line += (
				" — health %d/%d"
				% [sim.query_machine_health(index), sim.query_machine_max_health(index)]
			)
		lines.append(line)

	var unlisted: int = sim.query_machine_count() - healthy - listed
	if unlisted > 0:
		lines.append("… and %d more needing attention" % unlisted)
	if healthy > 0:
		lines.append("%d machines running" % healthy)

	var stalled: int = 0
	for index: int in range(sim.query_belt_count()):
		if sim.query_belt_is_stalled(index):
			stalled += 1
	if sim.query_belt_count() > 0:
		lines.append(
			"belts %d — %d stalled" % [sim.query_belt_count(), stalled]
		)

	# Walls, as one line and never one each: they are the most numerous thing a player builds
	# and the only question worth a HUD line is how many are being chewed through.
	var breached: int = 0
	for index: int in range(sim.query_wall_count()):
		if sim.query_wall_health(index) < sim.query_wall_max_health():
			breached += 1
	if sim.query_wall_count() > 0:
		lines.append("walls %d — %d damaged" % [sim.query_wall_count(), breached])

	_hud.text = "\n".join(lines)


## The Silo: the dial a player is carrying, whether the thing in front of them would take it,
## and a Painting in flight.
##
## **This is where the diegetic control is legible.** Loading is irreversible, so the whole
## bargain depends on a player knowing what they are about to commit and whether it would
## land *before* the key goes down — which is what `query_load_silo_refusal` is for, and why
## the refusal is a projection rather than a message after the fact. The wording lives here
## because a `Refusal` is a fact and a sentence about it is presentation, the same split
## `BuildGun.refusal_text` makes.
func _silo_lines(sim: Simulation) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	if sim.query_stratagem_count() == 0:
		return lines

	# A Painting first and in capitals, because it is the one state in which a player can do
	# nothing at all and the gauge is what the players covering them are watching.
	if sim.query_player_is_painting(0):
		var served: int = sim.query_player_paint_ticks_served(0)
		var required: int = maxi(sim.query_player_paint_ticks_required(0), 1)
		lines.append(
			"PAINTING %s x%d — %s %d%%"
			% [
				sim.query_player_paint_stratagem(0),
				sim.query_player_paint_charges(0),
				_gauge_bar(served, required),
				served * 100 / required,
			]
		)
		lines.append("HOLD STILL — letting go wastes the charges")
	else:
		var dial: String = sim.query_player_dial_stratagem(0)
		var line: String = "dial %s x%d" % [dial, sim.query_player_dial_charges(0)]
		# The same Silo the load key would commit to, through the one function both ask —
		# because a reason on screen about a different Silo from the one the key means is
		# worse than no reason at all.
		var aimed: Vector3i = PlayerController.silo_tile_for_loading(sim, 0)
		var refusal: int = sim.query_load_silo_refusal(
			0,
			aimed,
			sim.query_player_dial_stratagem_index(0),
			sim.query_player_dial_charges(0)
		)
		if refusal == Simulation.Refusal.NONE:
			line += " — LOAD READY (irreversible)"
		elif refusal != Simulation.Refusal.NO_SILO_THERE:
			line += " — %s" % load_refusal_text(refusal)
		lines.append(line)

	var wasted: int = sim.query_player_charges_wasted(0)
	if wasted > 0:
		lines.append("charges wasted to interrupted paintings: %d" % wasted)
	return lines


## What to tell a player about a load that will not happen.
##
## Separate from `BuildGun.refusal_text` because the reasons are different ones, and worded
## for the act: a Silo's refusals are about a commitment rather than about a tile, so
## "already loaded" has to read as "this is spent, not available".
static func load_refusal_text(refusal: int) -> String:
	match refusal:
		Simulation.Refusal.NONE:
			return ""
		Simulation.Refusal.NO_SILO_THERE:
			return "no silo there"
		Simulation.Refusal.OUT_OF_REACH:
			return "stand at the silo"
		Simulation.Refusal.SILO_ALREADY_LOADED:
			return "already loaded — fire it or lose it"
		Simulation.Refusal.NOT_ENOUGH_CHARGES:
			return "not enough charges assembled"
		Simulation.Refusal.BAD_CHARGE_COUNT:
			return "that is not a load"
		Simulation.Refusal.STRATAGEM_IS_LOCKED:
			return "not unlocked yet"
		Simulation.Refusal.NO_SUCH_STRATAGEM:
			return "no such stratagem"
		Simulation.Refusal.PLAYER_IS_PAINTING:
			return "both hands are on the designator"
		Simulation.Refusal.PLAYER_IS_DOWN:
			return "you are down"
		Simulation.Refusal.RUN_IS_OVER:
			return "the nest has fallen"
	return "cannot load"


## A bar of text standing for a fraction served. The Telegraph's gauge, reused: there is no
## audio yet and no texture, so a channel's progress is a row of cells that fills.
func _gauge_bar(served: int, required: int) -> String:
	var filled: int = clampi(served * TELEGRAPH_GAUGE_CELLS / maxi(required, 1), 0, TELEGRAPH_GAUGE_CELLS)
	return "[%s%s]" % ["#".repeat(filled), ".".repeat(TELEGRAPH_GAUGE_CELLS - filled)]


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


## Whether a Machine is a mine working deep enough to open a Breach, and has not opened its
## one yet. Asked of the Simulation rather than inferred from a Depth: what counts as deep is
## `depth.breach_tier`, which is tuning, and a renderer with its own opinion about it would be
## the wrong one the day somebody changed the file.
func _is_digging_up_a_breach(sim: Simulation, index: int) -> bool:
	var node: int = sim.query_node_under_machine(index)
	if node == -1 or sim.query_node_has_opened_a_breach(node):
		return false
	return sim.query_node_deep_crafts(node) > 0


## The klaxon for a Breach that deep mining has opened and that is about to let something out.
##
## As loud as a Wave's Telegraph and for the same reason: a hole appearing silently beside a
## Factory is the ambush the Telegraph exists to prevent (DESIGN.md). It says **where**,
## because unlike a Wave — which arrives at Breaches a player already knows — the only useful
## response to this one is to go and look at a tile they have never defended.
func _breach_opening_lines(sim: Simulation) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var total: int = maxi(sim.query_breach_telegraph_ticks(), 1)
	for index: int in range(sim.query_pending_breach_count()):
		var left: int = sim.query_pending_breach_ticks_remaining(index)
		var filled: int = mini((total - left) * TELEGRAPH_GAUGE_CELLS / total, TELEGRAPH_GAUGE_CELLS)
		var tile: Vector3i = sim.query_pending_breach_tile(index)
		lines.append(
			"!! BREACH OPENING AT (%d, %d) IN %ds [%s]"
			% [
				tile.x,
				tile.z,
				(left + Simulation.TICKS_PER_SECOND - 1) / Simulation.TICKS_PER_SECOND,
				"#".repeat(filled) + ".".repeat(TELEGRAPH_GAUGE_CELLS - filled),
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


## Every Siege Hulk on the Map, and every shell in the air.
##
## In capitals, like the Telegraph, because it is the same category of thing: a warning about
## something a player has to respond to rather than a reading they consult. What it reports is
## how much is left of the Hulk, how far out it is standing, and **that its front is armoured** —
## which is as far as this goes. It does not say where the weak point is: discovering that the
## front is the wrong end is the fight, and a line of UI naming the answer would spend it. What
## is on the Hulk itself is the glowing vent, which is where that information belongs.
func _siege_hulk_lines(sim: Simulation) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	for index: int in range(sim.query_enemy_count()):
		if sim.query_enemy_kind(index) != Simulation.ENEMY_KIND_SIEGE_HULK:
			continue
		var armour: int = sim.query_enemy_frontal_armour_percent(index)
		lines.append(
			"SIEGE HULK %d/%d — %s — ARMOURED FRONT %d%%"
			% [
				sim.query_enemy_health(index),
				sim.query_enemy_max_health(index),
				(
					"BOMBARDING from %dm, beyond every Turret"
					% Fixed.floor_to_int(sim.query_enemy_reach_metres(index))
					if sim.query_enemy_is_bombarding(index)
					else "closing"
				),
				armour,
			]
		)
	for index: int in range(sim.query_shell_count()):
		var at: FixedVec2 = sim.query_shell_impact_metres(index)
		lines.append(
			"INCOMING — %.1fs — (%d, %d)"
			% [
				float(sim.query_shell_ticks_remaining(index)) / float(Simulation.TICKS_PER_SECOND),
				Fixed.floor_to_int(at.x),
				Fixed.floor_to_int(at.z),
			]
		)
	return lines


## What leaving the Factory costs, on screen the whole time there is something out there worth
## leaving for.
##
## **The bill before the commitment, not after it** — the arrangement every refusal in this
## project has. A player deciding whether to sortie needs to know what a Hive is costing them per
## minute, how far from a wrench they will be, how much of the Factory is already hurt and how
## long until the next Wave; all four are projections the Simulation never reads back, so the
## panel cannot change the Run it describes.
func _sortie_lines(sim: Simulation) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var hives: int = sim.query_hive_count()
	if hives > 0:
		lines.append(
			"hives %d — hiding %d/min less heat — destroy one for good"
			% [hives, sim.query_hive_heat_shadow_per_minute()]
		)
	elif sim.query_definitions().hive_health > 0 and sim.query_tick() > 0:
		lines.append("hives cleared — the Nest hides everything it can again")

	var out: int = Fixed.floor_to_int(sim.query_player_metres_from_the_nest(VIEWED_PLAYER))
	var damaged: int = sim.query_machines_damaged()
	if hives > 0 or damaged > 0 or out > 20:
		lines.append(
			"away from the nest %dm — %d machines damaged — next wave %ds"
			% [out, damaged, sim.query_ticks_until_next_wave() / Simulation.TICKS_PER_SECOND]
		)
	return lines


## The Delivery the Nest is waiting on, item by item, and why it cannot be handed over yet.
##
## An acceptance criterion rather than a nicety: progression is physical, so a player aims
## their whole Factory at this bill, and one they cannot read is one they are guessing at.
## Every figure comes out of a query — which tier, what it wants, how much has arrived, the
## Depth it is gated at — so none of it can be stale or invented, and the reason it is
## refused is on screen before the walk across the Map rather than after it.
func _delivery_lines(sim: Simulation) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var next: int = sim.query_next_delivery()
	if next == -1:
		if sim.query_delivery_count() > 0:
			lines.append("delivery: every tier delivered")
		return lines

	var goods: PackedStringArray = PackedStringArray()
	for item_id: String in sim.query_delivery_goods(next):
		goods.append(
			"%s %d/%d"
			% [
				item_id,
				sim.query_delivery_goods_delivered(item_id),
				sim.query_delivery_goods_required(next, item_id),
			]
		)
	lines.append(
		"delivery %d/%d — %s — %s"
		% [
			next + 1,
			sim.query_delivery_count(),
			sim.query_delivery_display_name(next),
			", ".join(goods),
		]
	)
	# Depth on the same line as the gate it is, so "deliver deeper ore" and "mine deeper"
	# are not two separate readings a player has to put together.
	lines.append(
		"hand over (%s) — %s — depth %d of %d"
		% [
			OS.get_keycode_string(PlayerController.KEY_DELIVER),
			_delivery_text(sim.query_delivery_refusal(VIEWED_PLAYER)),
			sim.query_depth_reached(),
			sim.query_delivery_min_depth(next),
		]
	)
	return lines


## The Nest's store: what the Factory has banked past the open bill, and whether the player
## can take it. Its own lines rather than part of the Delivery block above, because the store
## is still there once the chain is finished and that block returns early when it is.
##
## The refusal reported is the one for **what the Build Gun is short of**, which is what the
## key actually withdraws (`PlayerController.KEY_WITHDRAW`) — so the reading and the key agree
## about the same act, rather than the HUD answering a question the key does not ask.
func _nest_store_lines(sim: Simulation) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var banked: PackedStringArray = PackedStringArray()
	for item_id: String in sim.query_nest_store_items():
		banked.append("%s %d" % [item_id, sim.query_nest_store(item_id)])
	lines.append(
		"nest store: %s — %d each max"
		% [
			"empty" if banked.is_empty() else ", ".join(banked),
			sim.query_nest_store_capacity_per_item(),
		]
	)

	var wanted: String = _what_the_build_gun_is_short_of(sim)
	if wanted == "":
		lines.append(
			"take (%s) — nothing on the Build Gun needs paying for"
			% OS.get_keycode_string(PlayerController.KEY_WITHDRAW)
		)
		return lines
	lines.append(
		"take %s (%s) — %s"
		% [
			wanted,
			OS.get_keycode_string(PlayerController.KEY_WITHDRAW),
			_withdraw_text(
				sim.query_withdraw_refusal(
					VIEWED_PLAYER, sim.query_definitions().item_index(wanted)
				)
			),
		]
	)
	return lines


## The first Item the Machine on the Build Gun costs more of than the player is carrying, or
## "" when it is free, affordable, or there is nothing on the gun. The same question
## `PlayerController._withdrawals_for_the_build_gun` asks, asked for the first Item only
## because a line of HUD text reports one reason at a time.
func _what_the_build_gun_is_short_of(sim: Simulation) -> String:
	var definitions: Definitions = sim.query_definitions()
	var machine: MachineDefinition = definitions.machine(
		sim.query_player_selected_machine(VIEWED_PLAYER)
	)
	if machine == null:
		return ""
	for slot: int in range(machine.build_cost_items.size()):
		var item_id: String = machine.build_cost_items[slot]
		if sim.query_player_item(VIEWED_PLAYER, item_id) < machine.build_cost_counts[slot]:
			return item_id
	return ""


## What to tell a player about taking materials back out of the Nest. Wording here, rule in
## the Simulation — the same split `BuildGun.refusal_text` makes.
func _withdraw_text(refusal: int) -> String:
	match refusal:
		Simulation.Refusal.NONE:
			return "ready"
		Simulation.Refusal.TOO_FAR_FROM_THE_NEST:
			return "walk to the Nest"
		Simulation.Refusal.NOTHING_TO_WITHDRAW:
			return "the Nest has none banked"
		Simulation.Refusal.NO_SUCH_ITEM:
			return "no such Item"
		Simulation.Refusal.RUN_IS_OVER:
			return "the Run is over"
		_:
			return "unavailable"


## What to tell a player about handing a Delivery over. Wording here, rule in the
## Simulation — the same split `BuildGun.refusal_text` makes.
func _delivery_text(refusal: int) -> String:
	match refusal:
		Simulation.Refusal.NONE:
			return "ready"
		Simulation.Refusal.TOO_FAR_FROM_THE_NEST:
			return "walk to the Nest"
		Simulation.Refusal.NOTHING_TO_DELIVER:
			return "nothing in hand the Nest wants"
		Simulation.Refusal.DEPTH_TOO_SHALLOW:
			return "mine deeper first"
		Simulation.Refusal.NO_DELIVERY_PENDING:
			return "nothing left to deliver"
		Simulation.Refusal.RUN_IS_OVER:
			return "the Run is over"
		_:
			return "unavailable"


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
	var yaw: float = Fixed.to_float(sim.query_player_yaw_turns(VIEWED_PLAYER)) * TAU

	# **The camera's response to its own weight (#29), and it is laid on top of the aim
	# rather than folded into it.** `query_player_camera_height_metres` and
	# `query_player_camera_pitch_turns` are where a round leaves from and where the Build
	# Gun's hologram snaps to; the bob, the landing dip and the lean are cosmetic, so they
	# are their own queries and they are added here. A bob folded into the aim would mean a
	# footfall moved where a shot went.
	#
	# All of it still comes out of the Simulation, so none of it is a second opinion and all
	# of it replays — and every size is hot-reloadable tuning, which is the point: nobody
	# can pick these numbers without playing.
	var bob_up: float = Fixed.to_float(
		sim.query_player_view_bob_vertical_metres(VIEWED_PLAYER)
	)
	var bob_side: float = Fixed.to_float(
		sim.query_player_view_bob_lateral_metres(VIEWED_PLAYER)
	)
	var dip: float = Fixed.to_float(sim.query_player_view_dip_metres(VIEWED_PLAYER))
	# The lateral bob is in the player's own frame, so it goes along their right vector.
	var right: Vector3 = Vector3(cos(yaw), 0.0, -sin(yaw))

	_camera.position = (
		Vector3(
			Fixed.to_float(ground.x),
			Fixed.to_float(sim.query_player_camera_height_metres(VIEWED_PLAYER)),
			Fixed.to_float(ground.z)
		)
		+ Vector3(0.0, bob_up - dip, 0.0)
		+ right * bob_side
	)
	# Turns, not radians: the Simulation holds the angle in turns because radians need
	# PI and PI is a float. One multiplication by TAU is the whole conversion.
	_camera.rotation = Vector3(
		(
			Fixed.to_float(sim.query_player_camera_pitch_turns(VIEWED_PLAYER))
			+ Fixed.to_float(sim.query_player_view_lean_pitch_turns(VIEWED_PLAYER))
		) * TAU,
		yaw,
		# A bank to the player's right is a negative roll about Godot's forward axis.
		-Fixed.to_float(sim.query_player_view_roll_turns(VIEWED_PLAYER)) * TAU
	)
	_camera.fov = Fixed.to_float(sim.query_player_field_of_view_degrees(VIEWED_PLAYER))


# ── The object in frame ───────────────────────────────────────────────────────
#
# **One view model, and whatever is in the player's hands is one field of it.**
# `WeaponViewmodel` is the whole of it, and it hangs off the camera so the model and the
# aim climb together. Everything it moves by is read out of the Simulation — the velocity,
# the kick, the tick a shot fired on, the rounds left in the player's pockets — so nothing
# here is a second opinion about the Run and all of it replays.
#
# **The Build Gun goes through the same door the weapons do.** #29 made `B` a holster: the
# Build Gun and the weapon swap places, one going down while the other comes up. It landed
# before #28 and built that as a second `Node3D` with its own meshes, its own sway and its
# own drop out of frame. #28 then arrived with the real article — `held_facts` hands back a
# struct whose `weapon` is an id and nothing more, `show_held` draws whatever that id names,
# and `draw` and `holster` are first-class animation *roles* — so the swap is now one
# assignment in `_sync_weapon`, and the stow, the model change and the draw come from
# `WeaponAnimator`. There is no longer a second answer to "what is in frame" to keep in step
# with the first.
#
# **The purchased arms are loaded at runtime from outside the repository, and are usually
# not there.** They are non-redistributable (`docs/ASSETS.md`), Godot cannot import an FBX
# at runtime, and nothing converted may be committed either — so
# `tools/assets/convert_weapons.sh` writes a GLB per weapon into a gitignored directory and
# `WeaponViewmodel` loads it if it finds it and draws two boxes if it does not. A clone
# without the packs is a playable, testable game; see `docs/ASSET_PIPELINE.md` section 7.
#
# The Build Gun is named in that directory like anything else, so the day somebody models
# one it arrives the same way, with the same clips, and this file does not change.

## The id the Build Gun is held under. Not a row in `content/gear.csv` — a Build Gun is not
## Gear and never fires — but `WeaponViewmodel` asks nothing of an id beyond being an id:
## whatever `<id>.glb` the gear directory holds is what is drawn, and the placeholder stands
## in when it holds nothing. `tests/cases/test_weapon_viewmodel.gd` pins that with this
## exact id.
const BUILD_GUN_HELD_ID: String = "build_gun"

var _weapon_view: WeaponViewmodel = null


## Puts whatever is in the player's hands in frame, where the Simulation says it should be.
##
## **The holster is one field of one struct.** `query_player_is_in_build_mode` is hashed
## Simulation state, so a replay reproduces a swap and in co-op what the other three are
## holding is drawable; what that mode *looks like* on its way across is `WeaponAnimator`'s,
## which is already timing a `holster` and a `draw` off the clip lengths of the model
## actually on screen. #29's `query_player_holster_blend` and
## `query_player_held_is_build_gun` describe the same transition a second time, from the
## other side of the boundary, and two authorities for one swap is the duplication this
## merge exists to remove — so they stay in the Simulation, where the Run's own tests pin
## them, and the renderer reads the mode.
func _sync_weapon(sim: Simulation) -> void:
	if _weapon_view == null:
		_weapon_view = WeaponViewmodel.new()
		_camera.add_child(_weapon_view)

	var facts: WeaponAnimator.Facts = _weapon_view.held_facts(sim, VIEWED_PLAYER)
	if sim.query_player_is_in_build_mode(VIEWED_PLAYER):
		facts.weapon = BUILD_GUN_HELD_ID
		# No reach and no magazine, which is the whole difference between a tool and a gun:
		# the placeholder barrel sizes itself off the reach, so a Build Gun reads as stubby,
		# and `is_melee` is what tells the animator there is no round to chamber and no
		# reload to play. Both are facts about the thing being held, not opinions about it.
		facts.reach_metres = 0.0
		facts.is_melee = true
	_weapon_view.show_held(facts)


## Whether the thing in the player's hands is in frame — their weapon, or the Build Gun
## while they are in build mode. For the smoke test.
func weapon_is_visible() -> bool:
	return _weapon_view != null and _weapon_view.visible


## Where the weapon sits relative to the camera, in metres. For the smoke test, which
## asserts it moves with what the Simulation says rather than with a remembered value.
func weapon_offset() -> Vector3:
	if _weapon_view == null:
		return Vector3.ZERO
	return _weapon_view.position


## Which animation role the weapon in frame is playing — `idle`, `fire`, `reload`, `draw`
## and the rest of `WeaponAnimator`'s vocabulary. For the smoke test.
func weapon_clip_role() -> String:
	if _weapon_view == null:
		return ""
	return _weapon_view.clip_role()


## Which held object's model is on screen — a weapon id, or `BUILD_GUN_HELD_ID`. Lags what
## the player is holding for exactly as long as putting the old one away takes. For the
## smoke test.
func weapon_model_id() -> String:
	if _weapon_view == null:
		return ""
	return _weapon_view.model_weapon()


## Whether a converted first-person model is in frame rather than the placeholder boxes.
## False on any clone without the purchased packs, which is the ordinary case.
func weapon_has_model() -> bool:
	return _weapon_view != null and _weapon_view.has_model()


## The view model itself, for anything that needs to put something other than a weapon in
## the player's hands — `WeaponViewmodel.held_facts` and `show_held` are that seam, and
## `_sync_weapon` is already its first caller: the Build Gun goes through it.
func weapon_viewmodel() -> WeaponViewmodel:
	return _weapon_view


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
## What the player is holding, what is on it, and what is left of them.
##
## Every figure read out of a query, so none of it can be stale and none of it is a second
## opinion. The effective numbers — damage, reach, scatter, rate — are the Simulation's own
## arithmetic rather than this layer multiplying percentages, which is what makes the line a
## player reads and the round that leaves the barrel one fact.
func _gear_lines(sim: Simulation) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()

	# What is in the hands, and what the left button therefore does. **The object in frame
	# is supposed to be the answer to this** — that is the whole reason build mode is a
	# holster rather than a flag in the corner — so the line is deliberately about the
	# *button* rather than about the mode: a player who has just pressed B wants to know
	# what their next click will do.
	lines.append(
		"BUILD GUN — left click places  [B] weapon"
		if sim.query_player_is_in_build_mode(VIEWED_PLAYER)
		else "WEAPON — left click fires  [B] build gun"
	)

	# What is left of the player, first and in capitals when it matters. A Downed player
	# reads one line and it counts down, because the only useful thing to know while
	# bleeding out is how long a teammate has.
	if sim.query_player_is_downed(VIEWED_PLAYER):
		lines.append(
			"DOWN — bleeding out, %ds left"
			% [sim.query_player_downed_ticks_remaining(VIEWED_PLAYER) / Simulation.TICKS_PER_SECOND]
		)
	elif sim.query_player_is_dead(VIEWED_PLAYER):
		lines.append(
			"DEAD — back at the Nest in %ds"
			% [sim.query_player_respawn_ticks_remaining(VIEWED_PLAYER) / Simulation.TICKS_PER_SECOND]
		)
	else:
		lines.append(
			"health %d/%d"
			% [
				sim.query_player_health(VIEWED_PLAYER),
				sim.query_player_max_health(VIEWED_PLAYER),
			]
		)

	var weapon: String = sim.query_player_weapon(VIEWED_PLAYER)
	if weapon.is_empty():
		lines.append("gear: nothing in your hands")
		return lines

	# The frame and what it actually does. `spread` is in degrees on the way out because
	# degrees is what `content/gear.csv` is written in; the Simulation works in turns.
	var reach: int = sim.query_player_weapon_range_metres(VIEWED_PLAYER)
	var line: String = (
		"gear: %s — %d dmg, %dm, %.1f° spread, %d tick"
		% [
			weapon,
			sim.query_player_weapon_damage(VIEWED_PLAYER),
			Fixed.floor_to_int(reach),
			Fixed.to_float(sim.query_player_weapon_spread_degrees(VIEWED_PLAYER)),
			sim.query_player_weapon_interval_ticks(VIEWED_PLAYER),
		]
	)
	if sim.query_player_weapon_is_melee(VIEWED_PLAYER):
		line += " — melee"
	lines.append(line)

	# The magazine, and `DRY` beside it, which is the one word that decides whether a player
	# backs off. The same arrangement a Turret's gauge has, and read off the same kind of
	# projection: `query_fire_refusal` is what the Simulation itself obeys.
	if not sim.query_player_weapon_is_melee(VIEWED_PLAYER):
		var magazine: String = (
			"%s %d — %d shots"
			% [
				sim.query_player_weapon_ammunition_item(VIEWED_PLAYER),
				sim.query_player_ammunition(VIEWED_PLAYER),
				sim.query_player_shots_remaining(VIEWED_PLAYER),
			]
		)
		if sim.query_fire_refusal(VIEWED_PLAYER) == Simulation.Refusal.OUT_OF_AMMUNITION:
			magazine += "  DRY"
		lines.append(magazine)

	# Every slot, named whether or not anything is in it. An empty slot is the thing a
	# player is trying to fill, so hiding it would hide the build goal.
	var fitted: PackedStringArray = PackedStringArray()
	for slot: int in range(sim.query_definitions().gear_slot_count()):
		var component: String = sim.query_player_component(VIEWED_PLAYER, slot)
		fitted.append(
			"%s %s"
			% [
				sim.query_definitions().gear_slot_id(slot),
				"—" if component.is_empty() else component,
			]
		)
	if not fitted.is_empty():
		lines.append("fitted: %s" % ", ".join(fitted))

	return lines


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
## Not decoration, and not only because a first-person controller judged on how it feels
## needs a surface to walk on. The generated surfaces are **physically based and mostly
## metal** — cast iron, welded steel, oiled steel — and a metal lit by an ambient *colour*
## has nothing to reflect, so it renders as a dark smear whatever its albedo says. The
## light here is therefore a sky the materials can see: ambient and reflections both come
## off it, which is what puts the sheen back on a boiler drum and the olive back on a
## housing. The palette was tuned in Blender renders and Blender's lighting is not
## Godot's; these numbers are the second half of that tuning.
func _sync_scenery(sim: Simulation) -> void:
	if _ground != null:
		return

	_environment = WorldEnvironment.new()
	var world: Environment = Environment.new()
	world.background_mode = Environment.BG_SKY
	var sky: Sky = Sky.new()
	var sky_material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	# Dieselpunk: a low, smoky, ochre sky rather than a clear blue one (DESIGN.md).
	sky_material.sky_top_color = Color(0.17, 0.19, 0.24)
	sky_material.sky_horizon_color = Color(0.49, 0.40, 0.29)
	sky_material.sky_curve = 0.12
	sky_material.ground_bottom_color = Color(0.11, 0.10, 0.09)
	sky_material.ground_horizon_color = Color(0.30, 0.25, 0.20)
	sky_material.ground_curve = 0.08
	# The haze the sun burns through, rather than a disc with a hard edge.
	sky_material.sun_angle_max = 18.0
	sky_material.sun_curve = 0.08
	sky.sky_material = sky_material
	world.sky = sky

	# Ambient *and* reflections off that sky. The reflection half is what a metal needs:
	# with no environment to mirror, `metallic = 1` is a material with nothing to show.
	world.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	world.ambient_light_sky_contribution = 1.0
	world.ambient_light_energy = 2.1
	world.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	# Filmic, because the sky is bright and the Machines are dark and a linear curve
	# cannot hold both — without it the ground blows out to white while a Smelter stays a
	# silhouette. The exposure sits a little under one so the ochre keeps its colour.
	world.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.tonemap_exposure = 1.15
	world.tonemap_white = 2.0

	# Contact shadow in the crevices of a body, which is most of what makes rivets,
	# gauges and frames read as parts rather than as texture.
	world.ssao_enabled = true
	world.ssao_radius = 0.9
	world.ssao_intensity = 1.6
	world.ssao_power = 1.4

	# Smog, so distance reads as distance. The grid otherwise runs to a hard horizon line
	# and a Factory fifty metres away is as crisp as the one under the player's nose.
	world.fog_enabled = true
	world.fog_mode = Environment.FOG_MODE_DEPTH
	world.fog_light_color = Color(0.46, 0.39, 0.31)
	world.fog_light_energy = 0.9
	world.fog_density = 0.0
	world.fog_depth_begin = 45.0
	world.fog_depth_end = 320.0
	world.fog_depth_curve = 1.4
	world.fog_sky_affect = 0.0

	_environment.environment = world
	add_child(_environment)

	_sun = DirectionalLight3D.new()
	# Low and off to one side — a late-afternoon industrial sun. Low enough that a stack
	# or a derrick throws a shadow long enough to see, which is half of what tells a
	# player how tall a thing is.
	# Behind a player's right shoulder as a Run opens — yaw 0 looks down -z — so the face
	# of a Machine a player is walking towards is the lit face and its shadow falls away
	# from them. A sun in front of the opening view would make every body a silhouette.
	_sun.rotation = Vector3(-0.72, 0.66, 0.0)
	_sun.light_energy = 3.0
	_sun.light_color = Color(1.0, 0.89, 0.73)
	_sun.shadow_enabled = true
	# Not fully black. A Machine in shadow still has to read as that Machine, and a
	# Factory half of which is unreadable at a glance defeats the point of Survey View.
	_sun.shadow_opacity = 0.9
	_sun.directional_shadow_max_distance = 160.0
	_sun.directional_shadow_blend_splits = true
	add_child(_sun)

	# A cool fill from the opposite side, carrying no shadow. The generated surfaces are
	# cast iron, soot and oiled steel — dark to begin with — and one sun leaves every face
	# turned away from it black. A Machine a player cannot read is a Machine they cannot
	# diagnose, and silhouette is a gameplay requirement here (docs/ASSET_PIPELINE.md), so
	# the far side of a boiler has to stay legible.
	_fill = DirectionalLight3D.new()
	_fill.rotation = Vector3(-0.41, -2.45, 0.0)
	_fill.light_energy = 1.1
	_fill.light_color = Color(0.72, 0.78, 0.92)
	_fill.shadow_enabled = false
	add_child(_fill)

	var tile_size: float = Fixed.to_float(sim.query_tile_size_metres())
	var span: float = float(GROUND_HALF_EXTENT_TILES * 2) * tile_size

	_ground = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(span, span)
	_ground.mesh = plane
	var surface: StandardMaterial3D = StandardMaterial3D.new()
	surface.albedo_texture = _grid_texture()
	# Dirt, not concrete: rough, unlit by any specular, and dark enough that the Machines
	# standing on it are the brightest thing in frame.
	surface.albedo_color = Color(0.60, 0.54, 0.47)
	surface.roughness = 1.0
	surface.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
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
	image.fill(Color(0.33, 0.30, 0.27))
	for along: int in range(size):
		image.set_pixel(along, 0, Color(0.42, 0.39, 0.35))
		image.set_pixel(0, along, Color(0.42, 0.39, 0.35))
	return ImageTexture.create_from_image(image)


## The Build Gun's hologram: the body of the selected Machine, drawn translucent on the
## tile the gun is aimed at, turned by the rotation the player is holding, and coloured by
## whether the Simulation would accept it.
##
## It is the Machine's own body rather than a box because the question a player is asking
## is "will *that* fit there", and a box cannot answer it — a derrick's legs and a boiler's
## drum occupy their footprint very differently.
##
## Everything here is a query. The aim comes from `BuildGun`, which derives it from where
## the Simulation says the camera is; the refusal comes from `query_build_refusal`, which
## is the same rule a build obeys. Nothing is remembered between frames, so there is no
## way for the hologram to promise a placement the Simulation would refuse.
func _sync_hologram(sim: Simulation) -> void:
	if _hologram == null:
		_hologram = MeshInstance3D.new()
		var fresh: StandardMaterial3D = StandardMaterial3D.new()
		fresh.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fresh.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_hologram.material_override = fresh
		add_child(_hologram)

	var selected: String = sim.query_player_selected_machine(VIEWED_PLAYER)
	var definition: MachineDefinition = sim.query_definitions().machine(selected)
	_hologram.visible = definition != null
	if definition == null:
		return

	var tile_size: float = Fixed.to_float(sim.query_tile_size_metres())
	var declared: Vector2i = Vector2i(definition.footprint_x, definition.footprint_z)
	var height: float = Fixed.to_float(definition.height)
	var dressing: String = _dressing_for(selected, declared, height)
	if _hologram_dressing != dressing:
		# `_dress` clears the material override where a body carries its own surfaces,
		# which is exactly what a hologram must not do — so the translucent skin goes back
		# on after.
		var skin: StandardMaterial3D = _hologram.material_override
		_dress(_hologram, selected, declared, tile_size, height)
		_hologram.material_override = skin
		_hologram_dressing = dressing

	var rotation: int = sim.query_player_build_rotation(VIEWED_PLAYER)
	var footprint: Vector2i = WorldGrid.rotated_footprint(declared.x, declared.y, rotation)
	var tile: Vector3i = BuildGun.aimed_tile(sim, VIEWED_PLAYER)

	_hologram.rotation = Vector3(0.0, _yaw_for_rotation(rotation), 0.0)
	_hologram.position = _footprint_centre(sim, tile, footprint)
	if not dressing.begins_with("res://"):
		_hologram.position.y += height * 0.5

	var refusal: int = sim.query_build_refusal(
		VIEWED_PLAYER, sim.query_player_selected_machine_index(VIEWED_PLAYER), tile, rotation
	)
	var tint: StandardMaterial3D = _hologram.material_override
	tint.albedo_color = (
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
