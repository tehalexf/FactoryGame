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

## A Node is drawn as a low slab, so a Miner standing on one does not hide it.
const NODE_HEIGHT_METRES: float = 0.4

## What the ore in the ground is painted, per Resource.
##
## **#52, and the lever is hue and material rather than brightness.** The playtest report was
## "I cant seem to find any ore in range for the miners", and the slab a player could not see
## was `Color(0.45, 0.32, 0.18)` — *four times* the albedo the palette's own surfaces run at
## (0.055 to 0.14), which makes it the one mistake #32 and #38 both paid for: a colour picked
## against a white background. It was already the brightest thing in frame and still invisible,
## because it shared its hue with the rust and the soot `ground.gdshader` paints the yard out
## of. **Nothing on the ground plane can win a contrast fight against the ground plane**, so
## these come back down into the palette and read as a seam rather than as a highlight, and
## the marks floating above them do the finding.
##
## Iron is a dark oxide and coal is a cold near-black. Up close that is the difference a player
## needs — which ore is this — and at range the beacon's colour carries it instead.
const ORE_IRON_GROUND: Color = Color(0.14, 0.072, 0.050)
const ORE_COAL_GROUND: Color = Color(0.042, 0.044, 0.055)

## What a Node's beacon is painted: the Resource, and whether this Run could work it at all.
##
## **Rose and cyan, and the first pair had to be thrown away on the evidence of a render.**
## Red is a mistake, amber is waiting, hazard yellow is attention, teal is a split flowing,
## warm orange is an output port, cool blue an input, cream a flow arrow — every one of those
## is a mark *about the Factory*, and a Node is the Map, like a Breach, so it has to read in a
## family the Factory does not use. Green and violet looked like the two hues left.
##
## They were not. **`HOLOGRAM_ALLOWED` is green**, and the scanner render is what showed why
## that matters: the scanner runs exactly when a Miner is on the Build Gun, which is exactly
## when a green hologram is standing on the ore — so the mark leading a player to the ore, the
## ore's own mark, and the ghost of the Machine about to land on it were three greens in one
## frame, and in the picture they could not be told apart. That is #48's finding again, which
## was a red mark on an orange arrow at the one tile the two are guaranteed to coincide: **the
## colours to check a mark against are the ones it is guaranteed to be seen beside, not the
## ones it merely shares a file with.**
##
## So iron is rose and coal is cyan — opposite ends of the wheel from each other, so the two
## Resources cannot be confused at range, and neither within reach of the hologram green, the
## dangling red or the starved amber.
##
## **Out of reach loses the Resource rather than dimming it.** A seam no unlocked Miner can
## lift is still worth seeing — it is what `content/deliveries.csv` is selling — but the
## actionable fact is "not yours yet", not which ore it is, and a dimmed version of a colour
## reads as a rendering artefact rather than as a state (`PENDING_BREACH_HEIGHT_METRES` records
## the same decision for a Breach about to open). So it goes inert steel: plainly a mark, and
## plainly not an invitation. `query_node_is_workable_now` decides which, and the objective
## line points by that same function — a beacon cannot promise ore the hint will not send a
## player to.
const ORE_IRON_COLOUR: Color = Color(0.98, 0.36, 0.72, 0.9)
const ORE_COAL_COLOUR: Color = Color(0.40, 0.90, 1.00, 0.9)
const ORE_OUT_OF_REACH_COLOUR: Color = Color(0.62, 0.65, 0.68, 0.75)

## A Node's beacon: how far above the ore the lowest segment floats, how tall each segment
## is, and the air between two of them. In metres.
##
## **One segment per Depth tier, stacked upward.** The third thing a Node has to say is how
## deep it is, and Depth is a small whole number — so it is counted out rather than coloured,
## which means "deeper" reads as "taller mark" and the tiers need no key. It also puts the
## richest ore highest on the skyline, which is correct: the seams are what the Delivery chain
## is selling.
##
## **The base is 1.3 m and a render is why it is not 5.** It was 5.0 first, reasoned from the
## marks a Machine built on this tile could wear — a Smelter's tag reaches `height` plus
## `SPLIT_MARK_CLEARS_THE_ROOF_METRES` — and the spawn render killed it twice over. The ticket
## said the nearest ore is 28 m away; it is **12.7 m**, and at 12.7 m a mark 5 m up sits 21
## degrees above the horizon, which is #41's symptom exactly: a bright thing in the sky with
## nothing visibly under it. The collision it was avoiding is gone anyway, because the beacon
## now leaves the moment *anything* is built on the Node (`query_node_is_built_on`) rather than
## when the Node is worked — so there is never a Machine under one to collide with.
##
## At 1.3 m the stack starts at chest height with open air under it, which is what keeps a mark
## over buildable ground from reading as a structure standing on it, and a Depth 3 seam still
## reaches 5.5 m and breaks the horizon from across the Map.
const NODE_BEACON_BASE_METRES: float = 1.3
const NODE_BEACON_SEGMENT_METRES: float = 1.0
const NODE_BEACON_GAP_METRES: float = 0.4

## How wide a beacon segment is drawn, as a fraction of a tile. Narrow, because a mark as wide
## as the tile it is about would read as a roof hanging over the ore.
const NODE_BEACON_WIDTH_FRACTION: float = 0.32

## The painted marking on the ore itself: how much of the tile it covers, how thick it is drawn
## and how far above the slab it lies. In metres except the fraction.
##
## **A second render is why this exists, and it is the finding that mattered most.** The stack
## alone is a *vertical* mark, and from Survey View — the one mode this game has for reading
## the whole Factory at a glance, looking down from 26 m — a vertical mark is a 0.6 m square
## seen end on. The survey shot showed no ore at all. So the ore wears a flat marking as well,
## and the two answer different questions: the stack is what you see from eye level across the
## yard, the marking is what you see from above and up close.
##
## It also fixes the first render's other complaint. A floating stack needs an owner (#41), and
## a bright patch directly beneath it is one — the two read as one mark rather than as a thing
## in the sky and a dark patch of ground that happen to share a tile.
##
## **Paint rather than a slab**, inset and millimetres thick, because the yard is already full
## of painted markings — `ground.gdshader` draws the grid as paint, and paint is the one thing
## on a floor that unambiguously is not an object standing on it. A Miner is placed *over* a
## Node, and a mark that read as occupied would trade one confusion for another.
const NODE_MARKING_FRACTION: float = 0.62
const NODE_MARKING_THICKNESS_METRES: float = 0.05
const NODE_MARKING_LIFT_METRES: float = 0.03

## The scanner: how often the pulse repeats, how far apart the pings are laid, how long the
## lit comet behind the head is, and how high off the ground it floats. Ticks and metres.
##
## **The player asked for this in these words: "a sort of scanner to ping the nearest node
## while putting down miners".** So the hint that leads you to ore is a mechanic rather than a
## line of text — a run of pings travelling the ground from your feet out to the nearest ore
## you could claim, in that ore's own colour, so the thing that leads you and the thing you
## arrive at are visibly one thing. It answers direction, distance and identity at once, which
## is three things a sentence would have to say one after another.
##
## **`SCANNER_PERIOD_TICKS` is a count of ticks and that is a hard rule, not a preference.**
## Nothing presentational in this project is timed by a clock: the audio director varies takes
## with `tick % count` and counts its cooldowns in ticks, and `WeaponViewmodel` computes a
## clip's time from the tick count and seeks it explicitly rather than letting the engine run
## it. A pulse is the same category of thing, and the property all three are keeping is that
## two Runs down the same script look the same. 90 ticks is a second and a half.
##
## Only the lit pings are drawn at all. A full dotted line standing permanently on the ground
## would be a path laid through the yard — scenery — where what a scanner is is a thing that
## *sweeps*, and the empty ground between sweeps is most of what makes it read as one.
const SCANNER_PERIOD_TICKS: int = 90
const SCANNER_STEP_METRES: float = 2.0
const SCANNER_TRAIL_METRES: float = 5.0
const SCANNER_PING_LIFT_METRES: float = 0.10
const SCANNER_PING_SIZE_METRES: float = 0.70

## How high a tile of Belt stands when it has no generated body — a low slab, so the
## Items riding it are what the eye follows.
const BELT_HEIGHT_METRES: float = 0.3

## How much of a tile a Wall fills. A shade under the full 2 m so neighbouring Walls read as
## separate blocks rather than as one extruded slab.
const WALL_WIDTH_FRACTION: float = 0.92

## A Wall at full health, and one chewed to nothing — as a **tint on the Wall's own
## surface** rather than as its colour outright. The fill between them is how far gone it is,
## because a Wall's health is the one thing a player needs to read off it at a distance.
##
## **It used to be a flat mid-grey, and a render showed why that was wrong twice over.** A
## Wall was the brightest object in frame — a cream slab standing beside Machines the same
## light rendered as iron — because a MultiMesh's instance colour multiplies the albedo in
## *linear* space while the palette's surfaces come out around 0.07, and 0.30 is four times
## that. And it was the one built thing in the game with no surface at all, which is a odd
## thing for the cheapest and most numerous. Both go away by making the material the
## palette's own `WeldedSteel` and the instance colour a multiplier on it: a whole Wall is
## riveted steel, and a chewed one reddens.
const WALL_WHOLE: Color = Color(1.0, 1.0, 1.0)
const WALL_RUINED: Color = Color(1.0, 0.26, 0.19)

## The surface a Wall wears. One of the committed palette materials the generated Machine
## bodies are made of, so a Wall belongs to the same world as the Factory it is protecting.
const WALL_MATERIAL: String = "res://assets/machines/materials/WeldedSteel.tres"

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

## How far behind its centre a Siege Hulk's vent is modelled, in **body heights** — the same
## normalised units `EnemyBodies` bakes a character into, so the weak point is a fraction of
## the Hulk and stays on its back whatever `siege_hulk.hit_height_metres` is tuned to.
const SIEGE_HULK_VENT_OFFSET: float = 0.30

## The shader that skins an Enemy out of its body's texture of bone poses. One file, shared by
## every kind and every surface, because what differs between a Crawler and a Breaker is which
## texture and which tint — not how a vertex gets where it goes.
const ENEMY_SKIN_SHADER: String = "res://game/enemy_skin.gdshader"

## The one surface every Enemy wears, graded into `dieselpunk_palette.json` by
## `tools/assets/enemy_grade.py` from the pack's own committed atlas.
##
## **It is a committed derived asset and a clone with no purchased packs has it**, like the
## generated Machine meshes, the icons and the Build Gun and unlike the weapon viewmodels —
## KayKit's characters are CC0, so a graded copy of their atlas is as redistributable as the
## atlas. The six characters share one texture, so there is one file here and not six.
const ENEMY_GRADED_ATLAS: String = (
	"res://assets/characters/kaykit_skeletons/graded/skeleton_texture_A.png"
)

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

## How far above **its own Machine's roof** a gauge hangs, in metres.
##
## Measured from `_machine_roof` and from nothing else. It used to be measured from a
## `MACHINE_GAUGE_HEIGHT_METRES` constant set "taller than any housing in the content", which
## is a second authority on how tall a Machine is and detaches the bar from everything that
## is not the tallest: a 2.0 m Turret wore its gauge 2.1 m clear of its own roof, which is
## #41's red rectangle floating over the Factory with nothing under it.
##
## **#50 then moved it from the declared housing to the roof, which is the same fix made
## twice.** `query_machine_height_metres` is what a player *stands on*, and a body may rise
## well above it — so a bar measured off the declaration is inside the superstructure of
## every Machine whose art has one. A Turret could never have shown that: neither shipped
## Turret has a body at all, so both draw a placeholder box sized from the declaration, and
## the two numbers are equal on the one Machine class that wears this mark.
##
## Small enough that the bar reads as sitting *on* the Machine, and comfortably under
## `STARVED_MARK_LIFT_METRES` so the amber starved tag stacks above the bar instead of
## poking through it. Both numbers were judged in a render.
const AMMUNITION_GAUGE_LIFT_METRES: float = 0.5

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

## The marks over the Map's ore, and the readable record of where they went and what colour
## they are. One MultiMesh however many Nodes at however many Depths (#52).
var _ore_beacons: MultiMeshInstance3D = null
var _ore_beacon_transforms: Array[Vector3] = []
var _ore_beacon_colours: Array[Color] = []
var _ore_marking_transforms: Array[Vector3] = []
var _ore_marking_colours: Array[Color] = []
var _scanner_pings: MultiMeshInstance3D = null
var _scanner_transforms: Array[Vector3] = []
var _scanner_colours: Array[Color] = []

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

## Every Enemy on the Map, as instances of one mesh **per kind**.
##
## **One MultiMesh a kind, never a node per Enemy.** ADR 0001 keeps Godot a renderer, and
## DESIGN.md's ~100-Enemy target rests on exactly this: idiomatic engine agents cap out
## around 150-250 before frame times collapse, where instanced array entries reach
## thousands. Milestone 1 draws twenty Crawlers through this path so that the Chaff tier
## needs no new drawing code at all — only more array entries.
##
## **One a kind rather than one in total, since #38**, and that is a change of count and
## not of rule: a Crawler and a Breaker drew the same procedural carapace out of one buffer,
## so the only thing separating "the sense of threat" from "the threat" on screen was a line
## of HUD. A MultiMesh can hold exactly one mesh, so distinguishable kinds mean a buffer a
## kind — three nodes, bounded by `EnemyKind.KIND_NAMES`, created on the first Enemy of each
## kind and never again. `test_baking_a_character_adds_no_node_to_the_view` is what holds
## that bound.
var _swarm_meshes: Dictionary = {}

## The instance data handed to each kind's MultiMesh, keyed by kind.
##
## **Sixteen floats an instance, not twelve**: twelve for the transform and four more for the
## per-instance custom data the skinning shader reads its animation frame out of. A MultiMesh
## with `use_custom_data` has the wider stride and **refuses a narrower array outright**,
## leaving every instance at the identity — which is what the Walls did before #32, four of
## them in a heap at the world origin. A kind drawn with the procedural fallback body has no
## shader and no custom data, so its buffer is the plain twelve.
var _swarm_uploads: Dictionary = {}

## The instance transforms of the whole swarm — every kind but the boss — in Enemy *index*
## order, in the flat twelve-float layout the Items use.
##
## Kept beside the per-kind upload buffers rather than derived from them, because this is the
## **readable record of what was drawn** and the per-kind buffers are bucketed by kind: a
## MultiMesh keeps its own copy on the rendering server where a headless test cannot see it,
## so an assertion about where Enemy 0 was drawn needs a record in Enemy 0's own order.
## Nothing ever reads a position back out of it to make a decision.
var _enemy_transforms: PackedFloat32Array = PackedFloat32Array()

## The baked character bodies, and one animator per kind holding that kind's clip lengths.
##
## Both are `RefCounted` and hold no node: `EnemyBodies` instantiates a character scene to read
## its rig and frees it inside one call, and `EnemyAnimator` touches no asset at all.
##
## **An animator a kind rather than one shared one**, because the clip lengths differ per kind
## and a shared animator would have to be told them again for every Enemy. It was, in the first
## version, and the cost was measurable: `EnemyBodies.Body.frame_counts()` duplicates a
## Dictionary, so a Wave of seventy paid for seventy Dictionary copies a frame. Told once, when
## the kind's body is baked.
var _enemy_bodies: EnemyBodies = EnemyBodies.new()
var _enemy_animators: Dictionary = {}

## Every Siege Hulk on the Map: its hull, and the vent on its back.
##
## Two MultiMeshes rather than one, and still **never a node per Enemy** — a Hulk is an entry in
## the same Enemy arrays as a Crawler (ADR 0001), so it is drawn the same way. It needs its own
## buffers only because it needs its own *mesh*: a boss drawn with the Crawler's body at the
## Crawler's size would be unreadable, and the vent has to be a second material for the weak
## point to be visible at all. Two fixed nodes however many Hulks arrive.
var _hulk_vent_meshes: MultiMeshInstance3D = null
## The Hulks' readable record of what was drawn, in Enemy index order, written by
## `_sync_enemies` along with every other kind's. Kept separate from `_enemy_transforms`
## because every Enemy test written before #38 means "the swarm" by that one.
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

## And how many it occupies when the MultiMesh also carries per-instance custom data:
## twelve for the transform and four more for the `INSTANCE_CUSTOM` the skinning shader
## reads. The engine refuses a buffer of the wrong stride rather than padding it.
const FLOATS_PER_SKINNED_INSTANCE: int = 16

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
## The yard the Factory stands in. Owned here rather than by `Main`, because it is drawn
## from the same queries everything else here is drawn from and holds no state of its own.
var _set_dressing: SetDressing = null
var _sun: DirectionalLight3D = null
var _fill: DirectionalLight3D = null
var _environment: WorldEnvironment = null

var _hud: Label = null
var _hud_layer: CanvasLayer = null
var _camera: Camera3D = null

## The death overlay (#54): a tint over the whole screen and two lines of large type.
## **Built once and then shown, hidden and recoloured** — the rule every other thing in this
## file obeys, so a Run that kills a player forty times does not grow the scene tree by a
## node. It holds nothing: the colour, the opacity and both strings are a function of three
## queries, read every frame.
var _mortality_tint: ColorRect = null
var _mortality_caption: Label = null
var _mortality_detail: Label = null

## The crosshair, held so that it can be taken away from a player who is not aiming at
## anything. See `_sync_mortality_overlay`.
var _crosshair_mark: Control = null

## What the HUD could say, and what it is saying.
##
## **Fifty-three appended lines, drawn over the Factory they describe.** Every one of them
## earned its place when it arrived and the sum of them is a wall. So the wall is still
## assembled — `hud_text` is it, and the suite still asserts against it — and what is
## *shown* is `_hud_brief`: what the player is doing, what is coming, and what is in
## trouble. The rest is one key away.
##
## The toggle is **not an Input Action**, for the reason saving is not: it does nothing to
## the Run, it leaves the hash where it was, and a replay has nothing to reproduce.
var _hud_full: String = ""
var _hud_brief: String = ""
var _hud_detailed: bool = false

## The Machine picker: a cell per Machine and one for the Belt tool, each with the icon of
## what the Machine makes, the key that reaches it, its build cost, and whether a Delivery
## still has it locked.
##
## Built once per definition set and repainted every frame, which is the same bargain the
## Machine bodies strike: what changes a lot is the selection and the lock state, and
## neither needs a node rebuilt.
var _picker: HBoxContainer = null
var _picker_cells: Array[PanelContainer] = []
var _picker_labels: PackedStringArray = PackedStringArray()
var _picker_icon_paths: PackedStringArray = PackedStringArray()
var _picker_locked: PackedInt64Array = PackedInt64Array()
var _picker_selected: int = -1
var _picker_built_for: int = -1

## The grid, parallel to `_picker_cells` and in the same key order `BuildChain.order` is in:
## which Machine each cell is about, where it is drawn, and what is on the left of it.
##
## The Belt's cell carries `machine_count()` for its Machine, which is the convention
## `query_player_selected_machine_index` and `Objective.pointed_at` already use for it.
var _picker_machines: PackedInt64Array = PackedInt64Array()
var _picker_columns: PackedInt64Array = PackedInt64Array()
var _picker_rows: PackedInt64Array = PackedInt64Array()
var _picker_input_icon_paths: PackedStringArray = PackedStringArray()
var _picker_next: int = -1
var _picker_arrows: Array[Label] = []

## The previewed Belt route: one flat slab a tile, in two buffers — the tiles that would be
## laid and the tiles that would be refused.
##
## **Two MultiMeshes rather than one with per-instance colour**, because the question a
## player is asking of it is binary and because two counts are two things a test can read.
## The arrows are a third, one a tile, pointing the way Items would travel, because a route
## with no direction on it is a route a player has to work out from which end they started
## dragging.
##
## Nothing here is remembered state. The route is recomputed every frame from the drag the
## controller is holding and `BeltRoute`, and the refusal comes from the Simulation's own
## projection — the same one the release will consult — so what is drawn red and what would
## be refused cannot disagree on the frame it matters.
var _belt_preview: MultiMeshInstance3D = null
var _belt_preview_refused: MultiMeshInstance3D = null
var _belt_preview_arrows: MultiMeshInstance3D = null
var _belt_preview_transforms: PackedFloat32Array = PackedFloat32Array()
var _belt_preview_refused_transforms: PackedFloat32Array = PackedFloat32Array()
var _belt_preview_arrow_transforms: PackedFloat32Array = PackedFloat32Array()

## The drag the controller is holding, handed over once a frame by `Main`.
##
## A reading on its way in, exactly as it is in the controller: the renderer is told where
## the button went down so it can draw the route that *would* cross, and the Simulation is
## still the only thing that knows a Belt was laid. `Main` is where the two meet because the
## controller and the view are both its children and neither may reach for the other.
## The port markers: an arrow on every face a Belt may dock against, inputs in one buffer and
## outputs in the other, for every Machine standing **and** for the one the hologram is about
## to land.
##
## `content/machine_ports.csv` has declared all of this since #19 and nothing drew any of it,
## which is why a player could not tell which face of a Smelter takes ore. The arrow points
## the way goods travel — into the body for an input, out of it for an output — because which
## way to point a Belt is the actual question being asked.
var _input_ports: MultiMeshInstance3D = null
var _output_ports: MultiMeshInstance3D = null
var _input_port_transforms: PackedFloat32Array = PackedFloat32Array()
var _output_port_transforms: PackedFloat32Array = PackedFloat32Array()

## What is wrong with the Factory, drawn where it is wrong.
##
## A Belt that feeds nothing and a Machine nothing reaches used to look exactly like a Belt
## feeding a Smelter — you found out by reading a line of HUD text over the thing it was
## describing. These are the two marks that make the difference visible in the world: a red
## post at a Belt end that leads nowhere or is fed by nothing, and an amber tag over a Machine
## the Simulation calls starved.
##
## **Both are queries asked every frame.** Nothing here remembers whether anything was
## connected, which is what makes demolishing the Smelter a Belt fed show up on the next
## frame with no bookkeeping anywhere — and what stops the renderer having a second opinion
## about a Factory it is only supposed to be drawing.
var _dangling_marks: MultiMeshInstance3D = null
var _starved_marks: MultiMeshInstance3D = null
var _belt_flow_arrows: MultiMeshInstance3D = null
var _dangling_transforms: PackedFloat32Array = PackedFloat32Array()
var _starved_transforms: PackedFloat32Array = PackedFloat32Array()
var _starved_tethers: MultiMeshInstance3D = null
var _starved_tether_transforms: PackedFloat32Array = PackedFloat32Array()
var _belt_flow_transforms: PackedFloat32Array = PackedFloat32Array()

## What a split is doing, drawn where it is doing it.
##
## #46 made a Machine share its output between its Belts in rotation and #47 decided which
## Belts are in that rotation at all; between them the Simulation knows three things a player
## could not see — that this Machine is a split, which branch cannot take its turn, and that
## what neither branch can carry is banking in the Machine rather than being lost. A mechanic
## a player cannot read is indistinguishable from a bug, which is the argument the Turret's
## Ammunition gauge and Heat's own visibility both make.
##
## Four buffers because absence has to be distinguishable from each state, the reason the
## Ammunition gauge is two meshes: a Machine with no tag is not a split, a **split** tag means
## goods are moving, a **banking** tag in its place means both branches are stopped and the
## buffer is growing, and at each branch's entry a post says whether that one is the blocked
## one. Every one of them is `query_*` asked this frame and nothing is remembered.
var _split_marks: MultiMeshInstance3D = null
var _banking_marks: MultiMeshInstance3D = null
var _branch_marks: MultiMeshInstance3D = null
var _blocked_branch_marks: MultiMeshInstance3D = null
var _split_transforms: PackedFloat32Array = PackedFloat32Array()
var _banking_transforms: PackedFloat32Array = PackedFloat32Array()
var _branch_transforms: PackedFloat32Array = PackedFloat32Array()
var _blocked_branch_transforms: PackedFloat32Array = PackedFloat32Array()

var _belt_drag_active: bool = false
var _belt_drag_anchor: Vector3i = Vector3i.ZERO
var _belt_drag_corner_axis: int = BeltRoute.ALONG_X


## Hologram colours. Green where a Machine would land, red where it would be refused —
## and the HUD says *why* in words, because a red box only says "no".
const HOLOGRAM_ALLOWED: Color = Color(0.35, 0.85, 0.45, 0.45)
const HOLOGRAM_REFUSED: Color = Color(0.9, 0.25, 0.2, 0.45)

## The colours of the two marks. Red for a dangling end, because it is a mistake; amber for a
## starved Machine, because it is a Factory that is only waiting. Deliberately the same two
## readings a HUD line used to carry, in the one place a player is already looking.
const DANGLING_COLOUR: Color = Color(0.95, 0.27, 0.22, 0.85)
const STARVED_COLOUR: Color = Color(1.0, 0.78, 0.22, 0.8)

## How high the marks float above what they are about, in metres. A post at a Belt end stands
## at about hip height; a Machine's tag hangs over its roof, where nothing is in the way of it.
##
## **"Its roof" is `_machine_roof` and not the declared housing**, since #50. A Miner's
## derrick reaches 8.24 m over a declared 1.80 and a Smelter's flue 7.75 over 1.50, so a tag
## measured off the declaration is five metres inside the thing it is labelling — drawn, the
## right colour, in the right place horizontally, and invisible. Three heights were rendered
## before this one was chosen: the declaration (the tag disappears into the derrick), a
## global lift big enough to clear the tallest body in the content (#41 reproduced exactly —
## the Turret's red bar floats seven metres over a low box with nothing under it), and the
## body each Machine actually draws, which is this one and the only one of the three that
## reads as a tag resting on a silhouette.
const DANGLING_MARK_HEIGHT_METRES: float = 1.1
const STARVED_MARK_LIFT_METRES: float = 1.2

## How thick the line that tethers a starved tag to the body under it is, as a fraction of a
## tile.
##
## **#66, and it is #41's rule arriving a fourth time.** #50's lift is right and was not
## touched: the tag rests a tag's height over the silhouette, which on a Miner's wide derrick
## cap reads as resting on it. What #50 rendered was a posed row of Machines at a composed
## distance; what the `running` shot found is the case that reading does not cover — a Steam
## Boiler's body tops out in a **narrow chimney**, so the same 1.2 m is 1.2 m of open sky over
## a pipe, and at twenty metres the eye joins the tag to nothing. The answer is not to move
## the tag, which would put it back inside something; it is to say whose it is, which is the
## answer #52 reached for an ore beacon floating over the ground ("the marking is what gives
## the floating stack an owner").
##
## Thin on purpose. A tether is punctuation and not a second mark: wide enough to survive a
## pixel at thirty metres, narrow enough that a Factory with six starved Machines is not six
## amber columns. Its length is `STARVED_MARK_LIFT_METRES` exactly, so one mesh serves every
## Machine however tall — the gap it fills is the same gap everywhere by construction.
const STARVED_TETHER_THICKNESS_TILES: float = 0.06

## How high a dangling post stands when the end it marks is **against a Machine's wall**, in
## metres — the branch post's clearance, for the branch post's reason.
##
## **#48 ruled this case out in writing and #56's first render found it.** The note on
## `BRANCH_MARK_HEIGHT_METRES` ends "nothing else in this file collides with [the port
## arrows], because a dangling end has no Machine behind it and therefore no arrow", and that
## sentence was true of every dangling end anybody had rendered. It is exactly false of the
## end this ticket is about: a Belt refused at a declared port is standing **on a dock tile**,
## which is where #36 draws a 3.2 m warm-orange arrow, and its 1.1 m post is a small red cube
## half inside the 0.9 m conveyor deck and lost among them. Rendered at four metres it is
## findable and at the distance a player reads a Factory from it is not there at all.
##
## So the one mark that matters most in the case the HUD is now explaining gets the height
## #48 already measured for exactly this collision. An end on open ground keeps the hip-height
## post, because there is nothing there for it to collide with and a post standing three
## metres over bare ground is #41's ownerless mark.
const DANGLING_AT_A_WALL_HEIGHT_METRES: float = 2.25

## The split marks' colours.
##
## A **cool process teal** for a split that is flowing, because it is not a complaint — it is
## a player being told the thing they built is working, and the two colours already spoken for
## are red for a mistake and amber for waiting. **Hazard yellow for banking**, taken from the
## palette's own `HazardYellow` rather than invented, because the two prop ids that wear it in
## the yard are the only other things in the world that do: it is this project's colour for
## "attention, not alarm", which is exactly what an overflowing Machine wants. And the blocked
## branch wears the **dangling red**, deliberately the same red a Belt end that leads nowhere
## wears: both are "this line is not carrying anything and you should look here", and a third
## red would be a third thing to learn.
const SPLIT_COLOUR: Color = Color(0.32, 0.80, 0.78, 0.85)
const BANKING_COLOUR: Color = Color(0.93, 0.74, 0.16, 0.9)
const BLOCKED_BRANCH_COLOUR: Color = Color(0.95, 0.27, 0.22, 0.9)

## How high a split's tag floats, in metres, and how big it is drawn.
##
## **Two lifts, because a render showed one number cannot satisfy both constraints.** The tag
## sits at whichever of them is higher, and each answers a different question:
##
## - `SPLIT_MARK_CLEARS_THE_BODY_METRES` is measured off the body actually drawn
##   (`_machine_roof`), and it is small. A Smelter's flue reaches about five metres over a
##   1.5 m housing, so a tag placed off the housing alone is inside the chimney — that is #41's
##   bug pointed inwards, and the first render of this found it. The tag has to clear what a
##   player can see.
## - `SPLIT_MARK_CLEARS_THE_ROOF_METRES` is measured off `query_machine_height_metres`, and it
##   is bigger than `STARVED_MARK_LIFT_METRES`. The marks a Machine can wear have to be an
##   *order* rather than numbers that happen not to collide: a Smelter with no ore and two
##   Belts off it wears two of them at once.
##
## Taking the max is what stops the second render's failure, which was the first one's inverse:
## at 2.1 m over a five-metre flue the tag was seven metres up, overlapping the HUD, with
## nothing visibly under it — which is #41's actual symptom. A tag resting just above a
## Machine's own silhouette belongs to it; one hovering two metres clear does not.
##
## Bigger than the posts, because this one has to read from thirty metres against a Factory
## rather than against bare ground.
const SPLIT_MARK_CLEARS_THE_BODY_METRES: float = 0.6
const SPLIT_MARK_CLEARS_THE_ROOF_METRES: float = 1.85
const SPLIT_MARK_SIZE_METRES: float = 1.3

## How high a branch post stands at its Belt's entry tile, in metres, and how big it is drawn.
##
## Two renders set this number and both findings are the same shape — the post was behind
## something, and the count, the colour and the position were all correct, so nothing but
## looking at the picture could have found it.
##
## At **0.7 m** it was under `belt.deck_height_metres`, which is 0.9: the mark was *inside the
## conveyor it is about*. It had been put below the hip-height dangling post on the argument
## that the two should read apart, which is a reason about the marks and not about the world.
##
## At **1.55 m** it cleared the deck and was still invisible, for a reason specific to this
## mark: **a branch's entry tile is a dock tile, which is exactly where #36 draws a port
## arrow**. Those are 3.2 m across, warm orange, and lie flat at deck height — so a small red
## post standing among them is red on orange at the one place they are guaranteed to coincide.
##
## **This note used to end "nothing else in this file collides with them, because a dangling
## end has no Machine behind it and therefore no arrow", and #56's first render falsified
## it.** An end that *is* against a Machine's wall — refused by a declared port
## rather than pointed at open ground — stands on a dock tile like any branch, and its
## hip-height post was half inside the conveyor and lost among the arrows. See
## `DANGLING_AT_A_WALL_HEIGHT_METRES`, which is this number reused for the collision it was
## measured against.
##
## So it stands **clear above the arrows** and is drawn as a pillar rather than a cube, which
## is what makes a row of them read as markers rather than as more freight on the line.
const BRANCH_MARK_HEIGHT_METRES: float = 2.25
const BRANCH_MARK_SIZE_METRES: float = 1.25

## The port markers' colours. Cool for what goes in and warm for what comes out, which is
## the one pair of colours a player does not have to be told the meaning of twice.
const PORT_INPUT_COLOUR: Color = Color(0.45, 0.72, 1.0, 0.9)
const PORT_OUTPUT_COLOUR: Color = Color(1.0, 0.66, 0.26, 0.9)

## How much bigger a port arrow is than a Belt's own flow arrow. Judged in a render: at
## 1.0 the two read as the same mark and the ports vanish into the line.
const PORT_MARKER_SCALE: float = 1.6

## How high the port markers float, in metres: the standard Belt deck height the table itself
## declares, so an arrow is at the height the Belt that docks there will be.
const PORT_MARKER_HEIGHT_METRES: float = 0.9

## How far from where the Build Gun is pointing a port arrow is still worth drawing, in
## tiles, measured to the arrow's own dock tile.
##
## **#66's second fault, and the number was bracketed by rendering.** Eight of the ten
## shipped Machines declare every tile of every face, so a Machine wearing all of them is a
## ring of arrows pointing outward in every direction — which has no tile in it, and which
## at a Factory's worth of Machines is a hedge. Drawn only around the aim, that same ring is
## a legend for the one Machine a player is deciding about, and #47's tile-by-tile promise is
## kept in full exactly where it is being asked.
##
## 6 is the shipped figure and three renders bracketed it. At 4 the Machine a player is
## placing *beside* loses its arrows, which is the one Machine whose output port they are
## lining the hologram up against. At 9 the picture is identical to 6 on the opening line, so
## the extra reach buys nothing and only widens the band a late Factory draws a hedge in. 6
## is a Belt run's worth of ground and about one Machine either side of the aim.
const PORT_ARROW_RANGE_TILES: int = 6

## The flow arrows' colour: a warm cream that reads against the dark decks, the green of a
## clear preview and the red of a refused one alike.
const FLOW_ARROW_COLOUR: Color = Color(0.98, 0.88, 0.62, 0.85)

## How high off the ground the previewed route floats, in metres. Just clear of the grid
## markings, so a preview over bare ground is unmistakably a preview and not a Belt.
const BELT_PREVIEW_HEIGHT_METRES: float = 0.06

## How tall a **refused** tile of the preview stands, in metres.
##
## A column rather than a slab, and that came out of a render: the commonest thing a route
## is refused by is a Wall, a Wall is 2.4 m of dark box, and a red slab 6 cm off the ground
## under one is a red slab nobody can see. The refusal has to read over the thing causing
## it, so it is drawn as the blocked *volume* and not as a blocked footprint.
const BELT_REFUSED_HEIGHT_METRES: float = 2.6

## How high the flow arrows float above the preview and above a running Belt's deck. Enough
## to clear the deck and the Items on it without becoming the thing a player looks at.
const FLOW_ARROW_LIFT_METRES: float = 0.08

## How far the ground plane extends past the **buildable** Map, in tiles. The plane used
## to stop exactly where the Simulation stops accepting a build, and the consequence was
## visible from anywhere on the Map: the world ended at a cliff of sky, which is the most
## placeholder thing a placeholder can do. The apron runs on well past the fence, so what
## a player sees at the boundary is a boundary with ground beyond it.
##
## The grid is not drawn out here — `game/ground.gdshader` paints markings only inside
## the Map — so there is no question about which part can be built on.
const GROUND_APRON_TILES: int = 96

## Where the generated Item icons live. #20 produced ten of them and nothing used one; a
## Machine's glyph is the Item it makes, which is what a player is actually hunting for when
## they go looking for a Smelter — and it means a new Machine gets a picture by having a
## Recipe rather than by somebody drawing one.
##
## **Committed, not quarantined.** `assets/generated/` is in the repository — these are
## SDXL output from committed prompts under `tools/aigen/`, not a derivative of a purchased
## pack — so a clone has every icon and an Item with no picture is a real gap rather than a
## checkout that was never linked. #59 closed the last one (`iron_plate`) and
## `tests/cases/test_item_icons.gd` is what stops another opening.
const ICON_DIRECTORY: String = "res://assets/generated/icons"

## How far off the bottom of the screen the Machine picker sits, and how big its icons are.
## Judged in a render: small enough to stay out of the way of the Factory, big enough that
## the glyph is a glyph and not a smudge.
const PICKER_MARGIN_PIXELS: float = 12.0
const PICKER_ICON_PIXELS: float = 40.0

## The picker's states, carried on a **border** and a backing of its own.
##
## **A render is why there is a stylebox here at all.** #36 drew the states by modulating the
## default `PanelContainer` theme, which is a near-transparent near-black: measured off the
## shot, every cell came out within a few counts of the ground behind it, the lit cell read
## as a *darker* box than its neighbours, and the one new state #53 adds was invisible
## outright. Three states that differ only in how dark a transparent box is are not three
## states. So the cells get an opaque backing — dark enough that white text reads over it
## wherever a player is standing — and the state is a border colour, which is unambiguous
## and does not fight the caption.
const PICKER_BACKING: Color = Color(0.07, 0.065, 0.06, 0.88)
const PICKER_RESTING_EDGE: Color = Color(0.42, 0.40, 0.36, 0.9)
const PICKER_SELECTED_EDGE: Color = Color(1.0, 0.78, 0.30, 1.0)
const PICKER_LOCKED_TINT: Color = Color(0.5, 0.5, 0.55, 0.65)
const PICKER_BORDER_PIXELS: int = 2

## The cell the objective line is talking about — #53's "say what is next", drawn on the
## hotbar as well as written at the top of the screen.
##
## **A fourth state, and it had to be a colour nothing else beside it owns.** Selected is
## warm amber and resting is a dim warm grey, so the hint goes cold: a saturated cyan, at
## full width around the cell, against a backing dark enough to carry it. The nearest other
## thing in frame is the blue of an input port marker, which is in the world rather than on
## the HUD and never touches this panel — checked in a render rather than assumed, which is
## the lesson #52 paid for.
const PICKER_NEXT_EDGE: Color = Color(0.35, 0.92, 1.0, 1.0)

## **There is deliberately no fourth colour for "selected and next".** A pale green was
## tried and thrown away on the evidence of a render: the one frame in which that state is
## common is a Belt drag, and a Belt drag already fills the screen with the green of a valid
## route — three greens in one shot, which is the pair #52 paid to learn. Selected wins
## instead, and it is the better rule anyway: the cyan's whole job is to get a player to
## pick the cell, so a cell they have picked has had the advice, and the objective line is
## still on screen saying what to do with it. A hint that goes on shouting after it has been
## taken is noise.

## The arrow between two columns of the hotbar: this stage feeds that one. Drawn between
## columns rather than between cells, because that is the true statement — every Machine in a
## column eats something made in the column before it, by construction (`BuildChain`), and an
## arrow per cell would claim a Pylon feeds a Silo.
const PICKER_FEEDS_ARROW: String = "→"

## How much room the arrow between two columns gets, and how much the gap before the group
## the chain does not feed gets. The second is wider on purpose: an arrow is a relationship
## and a gap is the absence of one, and they have to be told apart at a glance.
const PICKER_ARROW_PIXELS: float = 20.0
const PICKER_SEPARATOR_PIXELS: float = 34.0

## How many Machines in trouble the brief HUD will name before it counts them instead. Lower
## than the full list's: the brief is read at a glance mid-Wave.
const BRIEF_MACHINES_LISTED: int = 3

## How many Machines the HUD will name before it starts counting them instead. A line a
## Machine is readable at four and is a wall of text over the Factory at fifty, so the
## list is the ones in trouble and the rest are a number — which is also the order a
## player wants them in.
const MACHINES_LISTED: int = 5

## How long each arm of the crosshair is, in pixels. Small: it marks where the Build Gun
## points without becoming a thing a player looks at instead of the Factory.
const CROSSHAIR_ARM_PIXELS: float = 13.0


# ── Dying, where a player can see it happen (#54) ─────────────────────────────
#
# **The most consequential thing that happens to a player used to be invisible**, and a
# render is what established that rather than a reading of the code. `_gear_lines` does put
# `DEAD — back at the Nest in 7s` on the HUD in the same small type as `power 660/900 kW` —
# but `_gear_lines` is only reached by `hud_text()`, the whole wall behind `[H]`. The brief
# panel a player is actually reading is `_brief_lines`, and it has never mentioned death at
# all. So a solo death was presented by nothing on screen whatsoever except the weapon
# dropping out of frame. See `docs/images/death_before.png`, which is a dead player.
#
# The collapse in `_place_camera` is most of the fix; this is the half that answers "at a
# glance, without reading".
#
# Three rules it keeps, and each is the reason one of the numbers below is what it is.
#
# **It costs nothing.** `player.respawn_delay_seconds` is the entire price of dying
# (GLOSSARY.md, DESIGN.md), so there is no fade a player waits through and nothing to
# dismiss: the overlay comes up *inside* the collapse, driven by the very same
# `query_player_collapse_blend`, and leaves inside the rise. One number drives the view, the
# tint and the caption, so they cannot disagree about how far down a body is.
#
# **A Downed player must still be able to read the Map, and a dead one has nothing to read.**
# So the two tints are different in strength as well as in hue: Downed is light and warm,
# because the only useful thing a bleeding player can do is watch for a teammate coming, and
# a screen they cannot see through would take that away. Dead is darker and neutral, because
# there is nothing to do but wait — and that difference is the second half of what tells the
# two states apart, the posture being the first.
#
# **Neither is a flash.** The player has rejected four separate attempts at sound in this
# project for being too loud, and a sudden full-screen red is the visual form of exactly
# that: it startles, it is the thing a player remembers instead of the Factory, and it is
# unreadable on a cheap panel. These are tints over a scene that stays visible, eased in over
# the half-second a body takes to go over.

## How far down the screen is tinted at full collapse, and in what colour. The alpha is the
## ceiling: it is multiplied by the collapse blend, so nothing is ever more tinted than the
## body is down.
const DOWNED_TINT: Color = Color(0.32, 0.05, 0.04, 0.34)
const DEAD_TINT: Color = Color(0.02, 0.02, 0.03, 0.62)

## The caption, in type a player cannot fail to notice, against the HUD's own small face.
## **The word is the state and the line under it is what to do about it** — wait for a
## teammate, or wait out a clock.
const MORTALITY_CAPTION_FONT_PIXELS: int = 54
const MORTALITY_DETAIL_FONT_PIXELS: int = 20
const MORTALITY_CAPTION_COLOUR: Color = Color(0.95, 0.93, 0.90)
const MORTALITY_DETAIL_COLOUR: Color = Color(0.86, 0.82, 0.78)

## How far down the screen the caption sits, as a fraction of its height. Below the middle,
## because the middle of the screen is where the player is looking at the thing that killed
## them and a word over the top of it is a word in the way.
const MORTALITY_CAPTION_DROP: float = 0.14

## Clear air between the caption and the line under it, in pixels. See the note in
## `_sync_mortality_overlay` about why a centred full-rect label moves by half its offset.
const MORTALITY_LINE_GAP_PIXELS: int = 14


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
	_sync_siege_hulk_vents(sim)
	_sync_hives(sim)
	_sync_shell_markers(sim)
	_sync_belts(sim)
	_sync_walls(sim)
	_sync_items(sim)
	_sync_hologram(sim)
	_sync_belt_preview(sim)
	# After the hologram, because it draws the hologram's ports too and has to know whether
	# there is one.
	_sync_ports(sim)
	_sync_connection_marks(sim)
	_sync_split_marks(sim)
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


## How many Enemies are on screen. Instances of a mesh, so this is a count of transforms
## rather than a count of nodes — there is one node for each *kind*, however many arrive.
##
## With no argument: the whole swarm, every kind but the boss, which is what the Enemy
## tests written before #38 mean by it. With a kind: that kind's own buffer, which is how a
## test says "every Breaker is an instance of the Breaker's mesh".
func enemy_instance_count(kind: int = -1) -> int:
	if kind < 0:
		@warning_ignore("integer_division")
		return _enemy_transforms.size() / FLOATS_PER_INSTANCE
	if not _swarm_uploads.has(kind):
		return 0
	@warning_ignore("integer_division")
	return _swarm_uploads[kind].size() / _stride_for(kind)


## Which mesh a kind is drawn with, as the Mesh's own object id, or 0 for a kind nothing is
## drawn for. For the assertion that two kinds are not the same mesh — the cheapest version
## of the claim `machine_silhouette.py` makes about Machines, which is that two things a
## player has to respond to differently must not look the same.
func enemy_mesh_id(kind: int) -> int:
	if not _swarm_meshes.has(kind):
		return 0
	var node: MultiMeshInstance3D = _swarm_meshes[kind]
	if node.multimesh == null or node.multimesh.mesh == null:
		return 0
	return node.multimesh.mesh.get_instance_id()


## Which texture a kind's surface is actually painted with, as a `res://` path, or "" for a
## kind drawn through the procedural fallback. For the assertion that the *graded* atlas is
## what reaches the shader: a grade nothing samples is `prop_grade.py`'s own opening defect,
## and it is invisible from the grading side of the seam.
func enemy_surface_texture_path(kind: int) -> String:
	var material: ShaderMaterial = _enemy_surface_material(kind)
	if material == null:
		return ""
	var texture: Texture2D = material.get_shader_parameter("albedo_texture") as Texture2D
	if texture == null:
		return ""
	return texture.resource_path


## How metallic a kind's surface is. For the assertion that an Enemy is metal, which is what
## the light in this world is tuned for — see `_enemy_metallic`.
func enemy_surface_metallic(kind: int) -> float:
	var material: ShaderMaterial = _enemy_surface_material(kind)
	if material == null:
		return 0.0
	return float(material.get_shader_parameter("metallic"))


func _enemy_surface_material(kind: int) -> ShaderMaterial:
	if not _swarm_meshes.has(kind):
		return null
	var node: MultiMeshInstance3D = _swarm_meshes[kind]
	if node.multimesh == null or node.multimesh.mesh == null:
		return null
	var mesh: Mesh = node.multimesh.mesh
	if mesh.get_surface_count() == 0:
		return null
	return mesh.surface_get_material(0) as ShaderMaterial


## How big one instance of a kind was drawn, as the uniform scale on its basis. The bodies are
## baked one metre tall, so this is the height the Simulation said that Enemy is.
func enemy_instance_scale(kind: int, instance: int) -> float:
	if not _swarm_uploads.has(kind):
		return 0.0
	var buffer: PackedFloat32Array = _swarm_uploads[kind]
	var stride: int = _stride_for(kind)
	var base: int = instance * stride
	if instance < 0 or base + stride > buffer.size():
		return 0.0
	return Vector3(buffer[base + 0], buffer[base + 4], buffer[base + 8]).length()


## Which row of its body's pose texture one instance was drawn on — the per-instance animation
## frame, and the observable half of "the swarm is not in visible lockstep". Returns -1 for a
## kind drawn through the procedural fallback, which carries no custom data because it has no
## animation to carry.
func enemy_instance_pose_row(kind: int, instance: int) -> int:
	if not _swarm_uploads.has(kind) or _stride_for(kind) != FLOATS_PER_SKINNED_INSTANCE:
		return -1
	var buffer: PackedFloat32Array = _swarm_uploads[kind]
	var base: int = instance * FLOATS_PER_SKINNED_INSTANCE
	if instance < 0 or base + FLOATS_PER_SKINNED_INSTANCE > buffer.size():
		return -1
	return int(buffer[base + 12])


## How wide one kind's instance data is. Sixteen floats where a baked body gave it a skinning
## shader to feed, twelve where it is drawing the procedural fallback.
func _stride_for(kind: int) -> int:
	if not _swarm_meshes.has(kind):
		return FLOATS_PER_INSTANCE
	var node: MultiMeshInstance3D = _swarm_meshes[kind]
	if node.multimesh != null and node.multimesh.use_custom_data:
		return FLOATS_PER_SKINNED_INSTANCE
	return FLOATS_PER_INSTANCE


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


## Everything the HUD could say, as one block of text.
##
## **The whole wall, whether or not it is on screen.** It is what the suite asserts against
## and what `set_hud_detailed(true)` puts up; `hud_brief_text` is the triage and
## `shown_hud_text` is whichever of the two a player is actually reading.
func hud_text() -> String:
	return _hud_full


## What the HUD is showing: the brief, or the wall if the player asked for it.
func shown_hud_text() -> String:
	return "" if _hud == null else _hud.text


## The triaged HUD: what the player is doing, what is coming, and what is in trouble.
func hud_brief_text() -> String:
	return _hud_brief


## Whether the player has asked for the whole wall.
func hud_is_detailed() -> bool:
	return _hud_detailed


## Shows or hides the rest of the HUD. **Not an Input Action**, for the reason saving is
## not one: it does nothing to the Run, it leaves the hash where it was, and a replay has
## nothing to reproduce. `Main` reads the key where it reads Escape.
func set_hud_detailed(detailed: bool) -> void:
	_hud_detailed = detailed
	if _hud != null:
		_hud.text = _hud_full if _hud_detailed else _hud_brief


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


## Writes one instance with a yaw about Y, a uniform scale and a position, into a plain
## twelve-float buffer. `_write_instance` with a size, for the meshes that are modelled in the
## same normalised units a baked body is and placed by the Simulation's own figure for how big
## the thing is.
static func _write_scaled_instance(
	buffer: PackedFloat32Array, instance: int, where: Vector3, yaw: float, scale: float
) -> void:
	var base: int = instance * FLOATS_PER_INSTANCE
	var along: float = sin(yaw) * scale
	var across: float = cos(yaw) * scale
	buffer[base + 0] = across
	buffer[base + 1] = 0.0
	buffer[base + 2] = along
	buffer[base + 3] = where.x
	buffer[base + 4] = 0.0
	buffer[base + 5] = scale
	buffer[base + 6] = 0.0
	buffer[base + 7] = where.y
	buffer[base + 8] = -along
	buffer[base + 9] = 0.0
	buffer[base + 10] = across
	buffer[base + 11] = where.z


## Writes one instance of a skinned body: a yaw about Y, a uniform scale, a position, and
## the four floats of per-instance custom data the skinning shader reads.
##
## **Sixteen floats, and the stride is not negotiable.** A MultiMesh with `use_custom_data`
## expects twelve for the transform and four more after them, and assigning a narrower array
## to its `buffer` is refused outright — every instance stays at the identity, which is what
## the Walls did before #32: four of them in a heap at the world origin with an engine error
## a frame. The custom data carries the animation frame and the Enemy's remaining health, and
## nothing else: there is no per-Crawler object anywhere for anything else to live in.
##
## **The last two floats are written as zero and read by nothing, and that is deliberate
## headroom rather than slack.** `INSTANCE_CUSTOM.z` and `.w` cost nothing to carry — the
## stride is sixteen whatever is in them — so the next thing that wants to say something per
## Enemy has two channels without widening anything. Turning on `use_colors` instead would
## take the stride to twenty and with it this function, `_stride_for` and every accessor that
## divides by one.
static func _write_skinned_instance(
	buffer: PackedFloat32Array,
	instance: int,
	where: Vector3,
	yaw: float,
	scale: float,
	pose_row: int,
	health: float
) -> void:
	var base: int = instance * FLOATS_PER_SKINNED_INSTANCE
	var along: float = sin(yaw) * scale
	var across: float = cos(yaw) * scale
	buffer[base + 0] = across
	buffer[base + 1] = 0.0
	buffer[base + 2] = along
	buffer[base + 3] = where.x
	buffer[base + 4] = 0.0
	buffer[base + 5] = scale
	buffer[base + 6] = 0.0
	buffer[base + 7] = where.y
	buffer[base + 8] = -along
	buffer[base + 9] = 0.0
	buffer[base + 10] = across
	buffer[base + 11] = where.z
	buffer[base + 12] = float(pose_row)
	buffer[base + 13] = health
	buffer[base + 14] = 0.0
	buffer[base + 15] = 0.0


## The position an instance was drawn at, out of a MultiMesh buffer. A MultiMesh keeps its
## own copy on the rendering server where a headless test cannot see it, so the buffer
## this side is the only readable record of what was drawn.
static func _instance_position(buffer: PackedFloat32Array, instance: int) -> Vector3:
	var base: int = instance * FLOATS_PER_INSTANCE
	if instance < 0 or base + FLOATS_PER_INSTANCE > buffer.size():
		return Vector3.ZERO
	return Vector3(buffer[base + 3], buffer[base + 7], buffer[base + 11])


## The same instance as a `Transform3D`, for a MultiMesh that cannot be filled from a
## `PackedFloat32Array` in one go.
##
## **A MultiMesh with `use_colors` has a wider stride than twelve floats** — twelve for the
## transform and four more for the colour — so assigning a transforms-only array to its
## `buffer` is refused outright, and every instance stays at the identity. That is what the
## Walls did: four Walls drawn in a heap at the world origin, with an engine error a frame.
## The per-instance setters write into the engine's own buffer at whatever stride it is
## using, so they are the right door for a coloured MultiMesh; this array stays the readable
## record of what was drawn, because the engine-side copy is invisible to a headless test.
static func _instance_transform(buffer: PackedFloat32Array, instance: int) -> Transform3D:
	var base: int = instance * FLOATS_PER_INSTANCE
	if instance < 0 or base + FLOATS_PER_INSTANCE > buffer.size():
		return Transform3D.IDENTITY
	return Transform3D(
		Basis(
			Vector3(buffer[base + 0], buffer[base + 4], buffer[base + 8]),
			Vector3(buffer[base + 1], buffer[base + 5], buffer[base + 9]),
			Vector3(buffer[base + 2], buffer[base + 6], buffer[base + 10])
		),
		Vector3(buffer[base + 3], buffer[base + 7], buffer[base + 11])
	)


# ── Drawing ───────────────────────────────────────────────────────────────────

func _sync_nodes(sim: Simulation) -> void:
	var tile_size: float = Fixed.to_float(sim.query_tile_size_metres())
	_resize_pool(_node_meshes, sim.query_node_count(), tile_size, NODE_HEIGHT_METRES, ORE_IRON_GROUND)

	for index: int in range(sim.query_node_count()):
		var tile: Vector3i = sim.query_node_tile(index)
		var centre: FixedVec2 = sim.query_tile_centre_metres(tile)
		_node_meshes[index].position = Vector3(
			Fixed.to_float(centre.x),
			Fixed.to_float(sim.query_layer_height_metres(tile.y)) + NODE_HEIGHT_METRES * 0.5,
			Fixed.to_float(centre.z)
		)
		# The seam repainted every sync rather than once at construction, because a pooled
		# slab is reused for whichever Node took its index and the Resource is read off the
		# Simulation like everything else here. The material is this instance's own, from
		# `_resize_pool`, so writing it tints one Node.
		var skin: StandardMaterial3D = (
			_node_meshes[index].material_override as StandardMaterial3D
		)
		if skin != null:
			skin.albedo_color = _ore_ground_colour(sim.query_node_resource(index))

	_sync_ore_beacons(sim)
	_sync_ore_scanner(sim)


## What the ore in the ground is painted, from the Resource it yields.
##
## Iron is the default rather than a third case, because the Resources that exist are exactly
## the ones the Recipes mention and `sim/` names none of them — a Node yielding something this
## renderer has never heard of is an ordinary state and gets the ore colour, exactly as a
## Machine with no generated body gets a box.
static func _ore_ground_colour(resource: String) -> Color:
	return ORE_COAL_GROUND if resource == "coal" else ORE_IRON_GROUND


## The marks over every Node nothing has been built on: a flat marking painted on the ore, and
## one floating segment above it per Depth tier, coloured by the Resource — or inert where no
## Miner this Run owns could lift it.
##
## **It goes quiet the way the objective line does**, and on the same question the line picks a
## target by: `query_node_is_built_on`. A Node under a Machine is no longer ground a player can
## be sent to, whether or not that Machine is any good at working it — and a Miner standing
## idle on ore it cannot mine says so already, in amber, through `query_machine_is_starved`.
## Marking it twice would be two marks about one tile, and it is also what forced the beacon up
## into the sky in the first draft: with nothing ever built underneath, the stack is free to
## start at chest height where it belongs.
##
## One MultiMesh with per-instance colour and per-instance scale, so a Map of any number of
## Nodes at any Depth costs the scene tree one node — the arrangement the Walls have, and for
## the same reason. The scale is what lets one box be both a 5 cm painted square and a 1 m
## floating segment.
func _sync_ore_beacons(sim: Simulation) -> void:
	var tile_size: float = Fixed.to_float(sim.query_tile_size_metres())
	if _ore_beacons == null:
		_ore_beacons = MultiMeshInstance3D.new()
		var instanced: MultiMesh = MultiMesh.new()
		instanced.transform_format = MultiMesh.TRANSFORM_3D
		instanced.use_colors = true
		var unit: BoxMesh = BoxMesh.new()
		unit.size = Vector3.ONE
		instanced.mesh = unit
		_ore_beacons.multimesh = instanced
		var skin: StandardMaterial3D = StandardMaterial3D.new()
		skin.vertex_color_use_as_albedo = true
		skin.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		# Unshaded, for the reason an Ammunition gauge is: a mark a directional light can
		# darken is a mark a player fails to find at the one moment they are looking for it,
		# and the sun on this Map is 23 degrees up.
		skin.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ore_beacons.material_override = skin
		add_child(_ore_beacons)

	_ore_marking_transforms.clear()
	_ore_marking_colours.clear()
	_ore_beacon_transforms.clear()
	_ore_beacon_colours.clear()

	var segment: Vector3 = Vector3(
		tile_size * NODE_BEACON_WIDTH_FRACTION,
		NODE_BEACON_SEGMENT_METRES,
		tile_size * NODE_BEACON_WIDTH_FRACTION
	)
	var marking: Vector3 = Vector3(
		tile_size * NODE_MARKING_FRACTION,
		NODE_MARKING_THICKNESS_METRES,
		tile_size * NODE_MARKING_FRACTION
	)
	for index: int in range(sim.query_node_count()):
		if sim.query_node_is_built_on(index):
			continue
		var tile: Vector3i = sim.query_node_tile(index)
		var centre: FixedVec2 = sim.query_tile_centre_metres(tile)
		var ground: float = Fixed.to_float(sim.query_layer_height_metres(tile.y))
		var colour: Color = _ore_beacon_colour_of(sim, index)

		_ore_marking_colours.append(colour)
		_ore_marking_transforms.append(
			Vector3(
				Fixed.to_float(centre.x),
				ground + NODE_HEIGHT_METRES + NODE_MARKING_LIFT_METRES,
				Fixed.to_float(centre.z)
			)
		)
		for tier: int in range(maxi(sim.query_node_depth(index), 1)):
			_ore_beacon_colours.append(colour)
			_ore_beacon_transforms.append(
				Vector3(
					Fixed.to_float(centre.x),
					(
						ground
						+ NODE_BEACON_BASE_METRES
						+ NODE_BEACON_SEGMENT_METRES * 0.5
						+ tier * (NODE_BEACON_SEGMENT_METRES + NODE_BEACON_GAP_METRES)
					),
					Fixed.to_float(centre.z)
				)
			)

	var total: int = _ore_marking_transforms.size() + _ore_beacon_transforms.size()
	_ore_beacons.multimesh.instance_count = total
	for instance: int in range(_ore_marking_transforms.size()):
		_write_ore_instance(
			instance, _ore_marking_transforms[instance], marking, _ore_marking_colours[instance]
		)
	for instance: int in range(_ore_beacon_transforms.size()):
		_write_ore_instance(
			_ore_marking_transforms.size() + instance,
			_ore_beacon_transforms[instance],
			segment,
			_ore_beacon_colours[instance]
		)


## One instance of the shared unit box, scaled to what it is standing in for.
func _write_ore_instance(instance: int, at: Vector3, size: Vector3, colour: Color) -> void:
	_ore_beacons.multimesh.set_instance_transform(
		instance, Transform3D(Basis.IDENTITY.scaled(size), at)
	)
	_ore_beacons.multimesh.set_instance_color(instance, colour)


## What a Node's marks are painted: the Resource, or inert where no Miner this Run owns could
## lift it. `query_node_is_workable_now` decides, which is the function the objective line
## points by — so a mark cannot promise ore the hint will not send a player to.
func _ore_beacon_colour_of(sim: Simulation, index: int) -> Color:
	if not sim.query_node_is_workable_now(index):
		return ORE_OUT_OF_REACH_COLOUR
	return ORE_COAL_COLOUR if sim.query_node_resource(index) == "coal" else ORE_IRON_COLOUR


## How many beacon segments are floating over the Map's ore. For the smoke test; a player
## counts the segments over one Node to read its Depth.
func ore_beacon_count() -> int:
	return _ore_beacon_transforms.size()


## Where one beacon segment floats. The readable record of what was drawn, because the
## engine-side MultiMesh buffer is invisible to a headless test.
func ore_beacon_position(instance: int) -> Vector3:
	if instance < 0 or instance >= _ore_beacon_transforms.size():
		return Vector3.ZERO
	return _ore_beacon_transforms[instance]


## What one beacon segment is painted: the Resource, or inert for ore out of reach.
func ore_beacon_colour(instance: int) -> Color:
	if instance < 0 or instance >= _ore_beacon_colours.size():
		return Color.BLACK
	return _ore_beacon_colours[instance]


## How many pieces of ore wear a painted marking: one each, for the ore nothing is built on.
func ore_marking_count() -> int:
	return _ore_marking_transforms.size()


## Where one painted marking lies — on the ore itself, which is what anchors the stack
## floating above it to the ground it is about.
func ore_marking_position(instance: int) -> Vector3:
	if instance < 0 or instance >= _ore_marking_transforms.size():
		return Vector3.ZERO
	return _ore_marking_transforms[instance]


## The scanner: a comet of pings running the ground from the player's feet out to the nearest
## ore they could claim, while a Miner is on their Build Gun.
##
## **Three conditions, because "while putting down miners" is three facts**: the Build Gun is
## in hand, the Machine tool is out, and what is on it mines. A player holding a rifle or about
## to place a Smelter is not looking for ore, and a scanner that ran anyway would be the sort
## of thing a player turns off. Each is read off its own query every frame; nothing is
## remembered and there is no scanner mode to enter or leave.
##
## **And it goes quiet the moment the Factory is mining**, on `query_anything_is_mining` — the
## same question `Objective`'s opening line goes quiet on, so the two cannot disagree about
## whether the opening has taught itself. A player who walks straight to the ore and places a
## Miner barely registers that this existed, which is the whole intent.
##
## Deliberately **silent**. The brief offered a cue and `game/audio_director.gd` would take one,
## but this fires every 90 ticks for as long as a Miner is in hand, and a repeating tone is
## precisely the nagging the player has already rejected three alarms for. Nothing in this
## repository can listen, so an un-auditionable cue added to a mix with three outstanding
## complaints is the wrong risk. The lever if it is ever wanted is one `sustained_cues` entry
## keyed on `ore_scanner_ping_count() > 0`, with a hero take and a Kenney fallback like every
## other cue — but a *change*, on acquisition, rather than on every sweep.
func _sync_ore_scanner(sim: Simulation) -> void:
	if _scanner_pings == null:
		_scanner_pings = MultiMeshInstance3D.new()
		var instanced: MultiMesh = MultiMesh.new()
		instanced.transform_format = MultiMesh.TRANSFORM_3D
		instanced.use_colors = true
		var unit: BoxMesh = BoxMesh.new()
		unit.size = Vector3.ONE
		instanced.mesh = unit
		_scanner_pings.multimesh = instanced
		var skin: StandardMaterial3D = StandardMaterial3D.new()
		skin.vertex_color_use_as_albedo = true
		skin.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		skin.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_scanner_pings.material_override = skin
		add_child(_scanner_pings)

	_scanner_transforms.clear()
	_scanner_colours.clear()
	var node: int = _scanner_target(sim)
	if node != -1:
		_lay_the_pings(sim, node)

	_scanner_pings.multimesh.instance_count = _scanner_transforms.size()
	var size: Vector3 = Vector3(
		SCANNER_PING_SIZE_METRES, NODE_MARKING_THICKNESS_METRES, SCANNER_PING_SIZE_METRES
	)
	for instance: int in range(_scanner_transforms.size()):
		_scanner_pings.multimesh.set_instance_transform(
			instance, Transform3D(Basis.IDENTITY.scaled(size), _scanner_transforms[instance])
		)
		_scanner_pings.multimesh.set_instance_color(instance, _scanner_colours[instance])


## The ore the scanner is pinging, or -1 when it should not be running at all.
func _scanner_target(sim: Simulation) -> int:
	if sim.query_anything_is_mining():
		return -1
	if not sim.query_player_is_in_build_mode(SCANNING_PLAYER):
		return -1
	if sim.query_player_build_tool(SCANNING_PLAYER) != Simulation.BUILD_TOOL_MACHINE:
		return -1
	var definition: MachineDefinition = sim.query_definitions().machine(
		sim.query_player_selected_machine(SCANNING_PLAYER)
	)
	if definition == null or not definition.is_miner():
		return -1
	return sim.query_nearest_workable_node(SCANNING_PLAYER)


## Whose Build Gun the scanner reads. The player this view is drawn for, which is player 0
## until there is a reason for it to be anything else — the same assumption
## `_sync_weapon` and the hologram already make.
const SCANNING_PLAYER: int = 0


## Lays the lit part of the sweep along the ground between the player and the ore.
##
## The head is `query_tick` taken modulo the period, so it advances when the Simulation does
## and is in exactly the same place one period later. Pings are laid every
## `SCANNER_STEP_METRES` along the line and only the ones inside `SCANNER_TRAIL_METRES` behind
## the head are emitted at all, fading out towards the tail — so what is on the ground is a
## short comet travelling outward rather than a dotted path standing there.
func _lay_the_pings(sim: Simulation, node: int) -> void:
	var at: FixedVec2 = sim.query_player_position(SCANNING_PLAYER)
	var centre: FixedVec2 = sim.query_tile_centre_metres(sim.query_node_tile(node))
	var from: Vector2 = Vector2(Fixed.to_float(at.x), Fixed.to_float(at.z))
	var to: Vector2 = Vector2(Fixed.to_float(centre.x), Fixed.to_float(centre.z))
	var span: float = from.distance_to(to)
	if span < SCANNER_STEP_METRES:
		return
	var along: Vector2 = (to - from) / span

	var colour: Color = _ore_beacon_colour_of(sim, node)
	var ground: float = Fixed.to_float(
		sim.query_layer_height_metres(sim.query_node_tile(node).y)
	)
	var head: float = (
		span * float(posmod(sim.query_tick(), SCANNER_PERIOD_TICKS)) / float(SCANNER_PERIOD_TICKS)
	)
	# From zero, so the sweep visibly leaves the player's own feet — and so there is never a
	# tick with nothing lit at all. Starting at the first step instead left the first seventh
	# of every period empty, which reads as a scanner that is broken rather than one between
	# sweeps.
	var step: int = 0
	while float(step) * SCANNER_STEP_METRES <= span:
		var distance: float = float(step) * SCANNER_STEP_METRES
		var behind: float = head - distance
		step += 1
		if behind < 0.0 or behind > SCANNER_TRAIL_METRES:
			continue
		var lit: Color = colour
		lit.a = colour.a * (1.0 - behind / SCANNER_TRAIL_METRES)
		var on_the_ground: Vector2 = from + along * distance
		_scanner_colours.append(lit)
		_scanner_transforms.append(
			Vector3(on_the_ground.x, ground + SCANNER_PING_LIFT_METRES, on_the_ground.y)
		)


## How many pings of the sweep are lit. Zero whenever the scanner is not running, which is
## what the smoke test reads it for.
func ore_scanner_ping_count() -> int:
	return _scanner_transforms.size()


## Where one lit ping lies on the ground. The readable record of what was drawn.
func ore_scanner_ping_position(instance: int) -> Vector3:
	if instance < 0 or instance >= _scanner_transforms.size():
		return Vector3.ZERO
	return _scanner_transforms[instance]


## What one lit ping is painted: the target ore's own colour, faded towards the tail of the
## comet by its alpha.
func ore_scanner_ping_colour(instance: int) -> Color:
	if instance < 0 or instance >= _scanner_colours.size():
		return Color.BLACK
	return _scanner_colours[instance]


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
	skin.albedo_color = Color(0.10, 0.105, 0.095)
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
		var above: Vector3 = _gauge_height(sim, index)

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
			_gauge_height(sim, index),
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


## Where a gauge hangs: over the middle of its Machine's footprint, a fixed lift above
## **that Machine's own roof**.
##
## The height comes from `_machine_roof` — the taller of the housing the Simulation collides
## against and the body the renderer is drawing — so a gauge is *placed* on the thing it
## belongs to rather than *measured* against a constant, the rule a body already follows. A
## constant tall enough for every housing leaves the bar hanging in clear air over everything
## shorter, which is what #41 saw; the declaration alone puts it inside the superstructure of
## everything taller, which is what #50 saw.
func _gauge_height(sim: Simulation, index: int) -> Vector3:
	return _machine_centre(sim, index) + Vector3(
		0.0,
		_machine_roof(sim, index) + AMMUNITION_GAUGE_LIFT_METRES,
		0.0
	)


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


## Every Enemy on the Map, at the position the Simulation says it is at, wearing the
## character its kind is cast as and on the frame of the clip it is playing.
##
## One MultiMesh **a kind** and no node per Enemy (ADR 0001). That is the decision the
## ~100-Enemy target depends on, and #38 kept it while giving the swarm animation: the
## animation lives in a texture of skinning matrices that the vertex shader samples, and
## which row an Enemy is on arrives as four floats of per-instance custom data. There is
## nothing per Crawler anywhere on this side of the boundary — no object, no node, no
## remembered frame.
##
## No interpolation and no remembered previous frame, for the reason the Items have none:
## the Simulation moves a Crawler a fixed amount every tick and this draws it there. The
## animation obeys the same rule from the other direction — `EnemyAnimator` derives the frame
## from the tick, the Enemy's spawn tick and its serial, so nothing here is timed by a clock.
func _sync_enemies(sim: Simulation) -> void:
	var kinds: int = EnemyKind.KIND_NAMES.size()
	var counts: PackedInt32Array = PackedInt32Array()
	counts.resize(kinds)
	var swarm: int = 0
	for index: int in range(sim.query_enemy_count()):
		var kind: int = sim.query_enemy_kind(index)
		if kind < 0 or kind >= kinds:
			continue
		counts[kind] += 1
		if kind != Simulation.ENEMY_KIND_SIEGE_HULK:
			swarm += 1

	# One node a kind, **every kind, on the first sync** — before a Breach has released
	# anything. Eagerly rather than on the first Enemy of each kind, for two reasons that
	# point the same way: it is what keeps `test_an_enemy_is_never_a_node`'s claim the
	# strongest version of itself, zero growth rather than "no more than one a kind"; and
	# baking three characters is the most expensive thing this file does, so paying for it at
	# load is better than paying for it on the frame the first Wave arrives, which is the one
	# frame of a Run where a hitch is least affordable.
	#
	# The resize is unconditional for the same reason the loop is: a buffer left at its old
	# size would go on drawing a Wave that has been killed.
	for kind: int in range(kinds):
		_ensure_swarm_mesh(kind)
		_swarm_uploads[kind].resize(counts[kind] * _stride_for(kind))
	_enemy_transforms.resize(swarm * FLOATS_PER_INSTANCE)
	_hulk_transforms.resize(counts[Simulation.ENEMY_KIND_SIEGE_HULK] * FLOATS_PER_INSTANCE)

	var written: PackedInt32Array = PackedInt32Array()
	written.resize(kinds)
	var swarm_instance: int = 0
	var hulk_instance: int = 0
	for index: int in range(sim.query_enemy_count()):
		var kind: int = sim.query_enemy_kind(index)
		if kind < 0 or kind >= kinds:
			continue
		var where: FixedVec2 = sim.query_enemy_position_metres(index)
		var at: Vector3 = Vector3(Fixed.to_float(where.x), 0.0, Fixed.to_float(where.z))
		var yaw: float = _enemy_yaw(sim, index, kind)
		# The body is baked one metre tall, so the scale **is** the height the Simulation
		# resolves a round against. "A body is placed, never measured" from the other end:
		# a constant here would detach what a player shoots at from what they can see,
		# which is #41's ownerless red rectangle in a different costume.
		var height: float = Fixed.to_float(sim.query_enemy_hit_height_metres(index))
		if height <= 0.0:
			height = ENEMY_SIZE_METRES

		if kind == Simulation.ENEMY_KIND_SIEGE_HULK:
			_write_instance(_hulk_transforms, hulk_instance, at, yaw)
			hulk_instance += 1
		else:
			_write_instance(_enemy_transforms, swarm_instance, at, yaw)
			swarm_instance += 1

		var buffer: PackedFloat32Array = _swarm_uploads[kind]
		if _stride_for(kind) == FLOATS_PER_SKINNED_INSTANCE:
			_write_skinned_instance(
				buffer,
				written[kind],
				at,
				yaw,
				height,
				_pose_row(sim, index, kind),
				_health_fraction(sim, index)
			)
		else:
			# The procedural fallback is modelled at its own size rather than normalised, so
			# it is placed and not scaled — the rule it has always obeyed.
			_write_instance(buffer, written[kind], at, yaw)
		_swarm_uploads[kind] = buffer
		written[kind] += 1

	for kind: int in _swarm_meshes.keys():
		var node: MultiMeshInstance3D = _swarm_meshes[kind]
		node.multimesh.instance_count = counts[kind] if kind < kinds else 0
		if node.multimesh.instance_count > 0:
			node.multimesh.buffer = _swarm_uploads[kind]


## Which way an Enemy of this kind is pointing, in radians.
##
## A Siege Hulk holds a facing *point* — the Simulation needs one for the weak-point test,
## which is the sign of a dot product rather than an angle — so the `atan2` is here, on the
## outbound side of the boundary where a float belongs. Everything else faces the way the
## flowfield is sending it, which is a query like everything else: the Simulation decides
## where it is going and this draws it pointing that way. An Enemy on a tile the field cannot
## route keeps the heading it had, which is what the Simulation does with it too.
func _enemy_yaw(sim: Simulation, index: int, kind: int) -> float:
	if kind == Simulation.ENEMY_KIND_SIEGE_HULK:
		var where: FixedVec2 = sim.query_enemy_position_metres(index)
		var facing: FixedVec2 = sim.query_enemy_facing_point_metres(index)
		var nose_x: float = Fixed.to_float(facing.x) - Fixed.to_float(where.x)
		var nose_z: float = Fixed.to_float(facing.z) - Fixed.to_float(where.z)
		var length: float = sqrt(nose_x * nose_x + nose_z * nose_z)
		if length <= 0.0:
			return 0.0
		# `_write_instance` maps local +z to (sin yaw, cos yaw), so the yaw that points the
		# nose at a place is atan2 of the gap.
		return atan2(nose_x / length, nose_z / length)
	var heading: int = sim.query_flow_direction(sim.query_enemy_tile(index))
	return _yaw_for_direction(heading) if heading >= 0 else 0.0


## Which row of its body's pose texture this Enemy is on.
##
## Everything that decides it is a `query_*`, and `EnemyAnimator` is where the rule lives —
## this is only the wiring. A kind with no baked body has no texture to index and reads 0,
## which the fallback path never looks at.
func _pose_row(sim: Simulation, index: int, kind: int) -> int:
	var body: EnemyBodies.Body = _enemy_bodies.body_for(kind)
	if body == null or not _enemy_animators.has(kind):
		return 0
	var animator: EnemyAnimator = _enemy_animators[kind]
	var facts: EnemyAnimator.Facts = EnemyAnimator.Facts.new()
	facts.tick = sim.query_tick()
	facts.spawn_tick = sim.query_enemy_spawn_tick(index)
	facts.serial = sim.query_enemy_serial(index)
	facts.attacking = sim.query_enemy_is_attacking(index)
	# Holding is what is left of a Siege Hulk that has halted with nothing in reach; a
	# Crawler with a route is always walking it, so nothing else ever holds.
	facts.holding = (
		kind == Simulation.ENEMY_KIND_SIEGE_HULK and not sim.query_enemy_is_bombarding(index)
	)
	var cue: EnemyAnimator.Cue = animator.cue_for(facts)
	return body.row_of(cue.role, cue.frame)


## How much of an Enemy's health is left, as a fraction, for the shader to darken it by. A
## Crawler a Turret has been working on reads as hurt without a gauge over it — the Machines
## get gauges because a player has to *triage* them, and an Enemy only has to look wrong.
func _health_fraction(sim: Simulation, index: int) -> float:
	var most: int = sim.query_enemy_max_health(index)
	if most <= 0:
		return 1.0
	return clampf(float(sim.query_enemy_health(index)) / float(most), 0.0, 1.0)


## The MultiMesh one kind of Enemy is drawn through, created on the first one to arrive.
##
## A kind with a baked character gets the skinning shader and per-instance custom data; a kind
## with none gets the procedural carapace and no custom data at all. **A missing body is an
## ordinary state and not a warning**, the rule a Machine with no generated `.glb` already
## obeys: adding an Enemy kind is four tuning keys and a row in `content/waves.csv`, and it is
## never blocked on art.
func _ensure_swarm_mesh(kind: int) -> void:
	if _swarm_meshes.has(kind):
		return
	var body: EnemyBodies.Body = _enemy_bodies.body_for(kind)
	var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
	var instanced: MultiMesh = MultiMesh.new()
	instanced.transform_format = MultiMesh.TRANSFORM_3D
	if body != null:
		var animator: EnemyAnimator = EnemyAnimator.new()
		animator.set_frame_counts(body.frame_counts())
		_enemy_animators[kind] = animator
		instanced.use_custom_data = true
		instanced.mesh = _skinned_mesh(kind, body)
		# **No `custom_aabb`, and that is a decision rather than an omission.** The shader
		# moves vertices the engine cannot see, so the obvious thing is to declare a box big
		# enough to hold the animation — but a `custom_aabb` is in the *node's* space, and
		# this node sits at the view's origin while the Wave is forty metres away, so a box
		# around the origin culls the entire swarm. That is exactly what the first version
		# did: a render came back as empty ground with a Siege Hulk's vent floating on the
		# horizon, because the vent's MultiMesh had no such box and the bodies' did.
		#
		# What the engine computes instead is conservative here by construction. It takes
		# the mesh's own AABB — the **unnormalised** rest pose, 1.8 m for a Minion and 3.5 m
		# for a Golem — and scales it by each instance's transform, which is the body's
		# height. So a 1.6 m Crawler is bounded by a 2.9 m box and a 3.2 m Hulk by an 11 m
		# one: eighty per cent of headroom in every direction, which is far more than a
		# raised arm needs.
	else:
		instanced.mesh = (
			_siege_hulk_hull_mesh()
			if kind == Simulation.ENEMY_KIND_SIEGE_HULK
			else _crawler_mesh()
		)
	node.multimesh = instanced
	add_child(node)
	_swarm_meshes[kind] = node
	_swarm_uploads[kind] = PackedFloat32Array()


## One kind's baked mesh with every surface repainted through the skinning shader.
##
## The bake hands back the artist's own materials, because what a Crawler *is* belongs to the
## artist's file and what it *looks like in this game* belongs here — the same split
## `prop_grade.py` makes for the purchased props, and for the same reason: these are clean
## fantasy skeletons in a world of grimy cast iron, and a colour picked against a white
## background is a colour picked against the wrong thing (#32, measured on the Walls).
##
## **#38 made that split with a tint per kind, and #75 is the user looking at the result:
## *"the enemies look like shit honestly"*. They were right, and the reason is arithmetic
## rather than taste — a multiply cannot change a ratio.** Measured off the committed atlas
## through `Skeleton_Minion`'s own UVs, a Crawler's skull cell is a cold blue-white at linear
## luminance 0.551 and its boot cell is 0.067: eight to one, and one tint scales both by the
## same number, so whatever the tint is the Crawler is a bright skull with a dark smudge under
## it. Turning it down only moves the whole thing toward black, which is what shipped —
## measured off a `swarm bare` render, a Crawler's body sat at **0.007 against a ground at
## 0.046**, which is not a dark Enemy, it is a hole in the floor. And the hue was wrong in a
## direction no multiply reaches: there is no blue anywhere in this palette.
##
## So the surface is three things now, and none of them is a tint:
##
## * **A graded atlas** — `tools/assets/enemy_grade.py`, which is `prop_grade.grade_colour`'s
##   rule with this atlas's families and a shoulder tuned for a subject seen against the
##   *ground* rather than against a Machine. It closes the skull-to-boot ratio from 8:1 to
##   about 3.5:1 and sends bone to iron. It is loaded here rather than taken off the
##   material, which is deliberate: the pack embeds its image **inside the `.glb`**, so a
##   graded file beside the model would be `prop_grade.py`'s own opening defect — a grade
##   nothing samples — and `test_every_enemy_surface_wears_the_graded_atlas_rather_than_the_packs_own`
##   is what makes that unsayable.
## * **Metal.** `_sync_scenery` takes ambient and reflections off the sky *because* the
##   generated surfaces are mostly metal, and until #75 an Enemy was the one thing in the
##   world that was not — 0.05 metallic at 0.88 roughness has nothing to reflect under a sky
##   dome, which is most of why a backlit Crawler rendered as a silhouette.
## * **Grime and relief the atlas cannot carry**, derived in the shader from the rest pose.
##   See `game/enemy_skin.gdshader`; the short version is that these characters carry no
##   `COLOR_0`, so `prop_grade.deepen_grime`'s free per-prop occlusion has no counterpart and
##   #42's derived-relief answer is the one that transfers.
##
## **The per-kind tint survives and its job changed.** It no longer carries the *level* — the
## grade does — so it is near white and carries only a cast, which is a readability cue the
## kinds did not have before: everything used to be dark, so the only thing telling a Crawler
## from a Breaker was size (#49). It is still a multiply and it still cannot change a ratio,
## which is exactly why it is no longer asked to.
##
## **There was a second branch here and #49 removed it. The note is the deliverable.** The
## pack splits each character into a body material and an 80-vertex `Glow` material for its
## eye sockets, and #38 painted that surface with an ember emission and recorded it as the
## thing that would make a swarm readable at thirty metres. It renders nothing, and the
## documentation calling it the readability aid is what #49 was opened about.
##
## The plumbing was never the problem and that was checked rather than assumed: the baked
## mesh really does carry a surface named `Glow`, the branch really did fire, and the same
## emission on the *body* surface renders a glowing skeleton with full bloom. The geometry is
## simply inside the skull — 0.13 m behind its front on the Minion, and wider than the skull
## is, so what a player looks into is brow and cheek. All six committed characters carry the
## same 80-vertex `Glow` box at the same place on the shared rig, and a render at `pair` range
## shows the three that are cast with dark sockets, which is what settles it.
##
## It is gone rather than kept-in-case, because "it will light up the day somebody ships
## different art" is an untested claim about art nobody has, and an untested claim in a
## comment is exactly what produced this ticket. The two workarounds stay refused for #38's
## reasons, which are good ones: moving an artist's vertices outward is the renderer editing
## the model, and `depth_test_disabled` would draw a Crawler's eyes through the Factory wall
## it is standing behind. **What makes the kinds readable instead is size** — see
## `tests/cases/test_enemy_silhouette.gd` and `enemy.breaker_hit_height_metres`.
##
## The `Glow` surface is still drawn; it just wears the body's own tint like everything else,
## which is what it looks like from outside a closed skull anyway. The Siege Hulk's vent is
## untouched and is still the project's one piece of emissive geometry — and the difference
## worth keeping in mind is that the vent is *built here*, sized and placed against the body
## it sits on, rather than hoped for in an asset.
func _skinned_mesh(kind: int, body: EnemyBodies.Body) -> ArrayMesh:
	for surface: int in range(body.mesh.get_surface_count()):
		var painted: ShaderMaterial = ShaderMaterial.new()
		painted.shader = load(ENEMY_SKIN_SHADER)
		painted.set_shader_parameter("pose", body.pose)
		painted.set_shader_parameter("texels_per_bone", EnemyBodies.TEXELS_PER_BONE)
		# **The artist's material is no longer read at all, and that is the change.** It used
		# to be asked for its `albedo_texture` so the pack's own atlas could be tinted; the
		# graded copy goes on instead, whatever the `.glb` embedded, because a surface the
		# grade did not cover would be the one thing in a Wave still wearing bone-white. The
		# pack embeds its image *inside* the GLB rather than naming a file beside it, so there
		# is nothing to recover and nothing to prefer.
		var texture: Texture2D = load(ENEMY_GRADED_ATLAS) as Texture2D
		if texture != null:
			painted.set_shader_parameter("albedo_texture", texture)
			painted.set_shader_parameter("has_albedo_texture", true)
		painted.set_shader_parameter("albedo_tint", _enemy_tint(kind))
		painted.set_shader_parameter("metallic", _enemy_metallic(kind))
		painted.set_shader_parameter("roughness", _enemy_roughness(kind))
		body.mesh.surface_set_material(surface, painted)
	return body.mesh


## What each kind's graded texture is multiplied by — a cast, not a level.
##
## Before #75 these were 0.17 to 0.25 and were doing the whole job: the atlas was bone-white
## and this was what stood between it and a palette running 0.055 to 0.14. The grade owns the
## level now, so these are near white and the only thing left in them is **which kind**, which
## is a cue the Wave did not previously have — everything was dark, so size was carrying the
## entire distinction (#49) and a Crawler and a Breaker at thirty metres were the same smudge
## in two heights.
##
## Warm for the Crawler, because rust is what settles on something nobody maintains; cold for
## the Breaker, because the thing a player has to *answer* should read as plated rather than
## as a bigger Crawler; and the Siege Hulk keeps the cast iron its procedural hull wears, so
## the body and the hull a kind with no character would draw agree.
func _enemy_tint(kind: int) -> Color:
	match kind:
		Simulation.ENEMY_KIND_BREAKER:
			return Color(0.91, 0.95, 1.0)
		Simulation.ENEMY_KIND_SIEGE_HULK:
			return Color(0.92, 0.90, 0.88)
	return Color(1.0, 0.88, 0.78)


## How metallic each kind reads. A Lambertian body beside a metal Machine renders twice as
## bright from the same albedo whatever the texture says — `prop_grade.py`'s finding — so the
## armoured kinds are metal and the bare one is not.
func _enemy_metallic(kind: int) -> float:
	match kind:
		Simulation.ENEMY_KIND_BREAKER:
			return 1.0
		Simulation.ENEMY_KIND_SIEGE_HULK:
			return 1.0
	return 0.8


## And how rough, against the palette's own figures: a Breaker is `WeldedSteel` at 0.45,
## a Crawler and the boss are `CastIron` at 0.62.
##
## **The note that stood here is corrected rather than deleted.** It said the Crawler was
## pushed to 0.88 because at 0.62 the skulls caught a hard specular off the low sun and read
## as glazed pottery. That was a true observation about a **dielectric** at 0.17 albedo: a
## rough-plastic highlight on a near-black body is a bright smear with nothing under it. At
## metallic 1 the same highlight *is* the surface — a metal's reflection is coloured by its
## own albedo rather than sitting white on top of it — so the fix was the material model and
## not the number, and 0.88 on a metal is a grey felt Crawler. The shader then spreads this
## either side of itself off the grime field, because one roughness over a whole body is one
## highlight over a whole body.
func _enemy_roughness(kind: int) -> float:
	match kind:
		Simulation.ENEMY_KIND_BREAKER:
			return 0.45
		Simulation.ENEMY_KIND_SIEGE_HULK:
			return 0.62
	return 0.62


## The glowing vent on the back of every Siege Hulk on the Map.
##
## **The hull moved into `_sync_enemies` with every other kind in #38** — a Hulk is an entry in
## the same Enemy arrays as a Crawler (ADR 0001), so it is drawn the same way, and since every
## kind now has its own buffer there is nothing left for a separate hull path to do. The vent
## did not move, and that is the point: it is a *second* mesh standing behind the body along
## the Hulk's own facing, and it is the only place in this project where geometry carries a
## rule. The front shrugs off 85% of a hit and the back does not; nothing tells a player that
## in words; so the glowing end is the end that is not armoured.
##
## Unshaded, for the reason a Turret's gauge is: a weak point a directional light can darken is
## a weak point a player misreads at the worst moment.
func _sync_siege_hulk_vents(sim: Simulation) -> void:
	if _hulk_vent_meshes == null:
		_hulk_vent_meshes = _instanced(_siege_hulk_vent_mesh())

	var total: int = 0
	for index: int in range(sim.query_enemy_count()):
		if sim.query_enemy_kind(index) == Simulation.ENEMY_KIND_SIEGE_HULK:
			total += 1
	_hulk_vent_transforms.resize(total * FLOATS_PER_INSTANCE)

	var instance: int = 0
	for index: int in range(sim.query_enemy_count()):
		if sim.query_enemy_kind(index) != Simulation.ENEMY_KIND_SIEGE_HULK:
			continue
		var where: FixedVec2 = sim.query_enemy_position_metres(index)
		var size: float = Fixed.to_float(sim.query_enemy_hit_height_metres(index))
		if size <= 0.0:
			size = SIEGE_HULK_SIZE_METRES
		# Exactly the body's own transform. The vent is modelled on the back of a one-metre
		# body, so placing it *with* the body is what keeps the two together — there is no
		# offset here to disagree with the one in the mesh.
		_write_scaled_instance(
			_hulk_vent_transforms,
			instance,
			Vector3(Fixed.to_float(where.x), 0.0, Fixed.to_float(where.z)),
			_enemy_yaw(sim, index, Simulation.ENEMY_KIND_SIEGE_HULK),
			size
		)
		instance += 1

	_hulk_vent_meshes.multimesh.instance_count = total
	if total > 0:
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


## The vent on a Siege Hulk's back: a glowing panel, modelled **on the back of a body one
## metre tall** and drawn with the Hulk's own transform.
##
## Unshaded, for the reason a Turret's gauge is: a weak point a directional light can darken is
## a weak point a player misreads at the worst moment.
##
## Two things changed in #38 and both came out of a render. It is modelled in the body's own
## normalised units, as `EnemyBodies` bakes a character, so it is a *fraction* of the Hulk and
## cannot be left behind if `siege_hulk.hit_height_metres` is ever tuned. And the offset behind
## the body is **modelled into the mesh** rather than applied to the instance, so the vent is
## placed with exactly the transform the body is placed with and there is no second piece of
## arithmetic to get wrong.
##
## Its first version was sized against the old procedural hull — a wide low sled four metres
## across — and when the body became a Golem the same block rendered as a saturated orange
## crate standing in front of the boss and hiding it completely. Worth recording because the
## failure is the one #41 had: a mark sized off a constant rather than off the thing it marks.
func _siege_hulk_vent_mesh() -> Mesh:
	var built: SurfaceTool = SurfaceTool.new()
	built.begin(Mesh.PRIMITIVE_TRIANGLES)
	var block: BoxMesh = BoxMesh.new()
	block.size = Vector3.ONE

	# A grille rather than a block: one glowing panel at the small of the back with two
	# louvres across it. Read off a render — the first version stood a tall pillar either
	# side of the panel and the three together made a bracket shape that read as a piece of
	# HUD stuck to the model rather than as an opening in it.
	built.append_from(block, 0, Transform3D(
		Basis.from_scale(Vector3(0.20, 0.15, 0.06)),
		Vector3(0.0, 0.50, -SIEGE_HULK_VENT_OFFSET)
	))
	for louvre: int in [-1, 0, 1]:
		built.append_from(block, 0, Transform3D(
			Basis.from_scale(Vector3(0.25, 0.022, 0.075)),
			Vector3(0.0, 0.50 + float(louvre) * 0.055, -SIEGE_HULK_VENT_OFFSET)
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
		# Left unsized here: the size is written every sync from `query_wall_height_metres`,
		# just below, because the Simulation owns how tall a Wall is.
		instanced.mesh = BoxMesh.new()
		# The palette's own plate, tinted per instance by how chewed the Wall is. Duplicated
		# rather than used directly, because the resource is shared with the Machines and
		# switching vertex colouring on for a Wall must not switch it on for a Smelter.
		var plate: StandardMaterial3D = load(WALL_MATERIAL) as StandardMaterial3D
		var skin: StandardMaterial3D = (
			plate.duplicate() if plate != null else StandardMaterial3D.new()
		)
		skin.vertex_color_use_as_albedo = true
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
		_wall_meshes.multimesh.set_instance_transform(
			index, _instance_transform(_wall_transforms, index)
		)
		_wall_meshes.multimesh.set_instance_color(
			index,
			WALL_RUINED.lerp(
				WALL_WHOLE, clampf(float(sim.query_wall_health(index)) / float(whole), 0.0, 1.0)
			)
		)


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

	# How high the deck is comes from the Simulation, because #30 made a Belt solid and
	# `belt.deck_height_metres` is what a player stands on — an Item riding 10 cm above or
	# below the surface somebody is walking on would read as a bug. The slab placeholder
	# keeps its own lower deck, because that *is* a different, shorter object.
	var deck: float = (
		Fixed.to_float(sim.query_belt_deck_height_metres())
		if _body(BELT_BODY) != null
		else BELT_HEIGHT_METRES
	)
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
		# The overlay goes in *before* the HUD label so the tint sits behind the text rather
		# than over it: a player who has just died still wants to read the Wave countdown.
		_build_mortality_overlay()
		_hud_layer.add_child(_mortality_tint)
		_hud_layer.add_child(_hud)
		_hud_layer.add_child(_mortality_caption)
		_hud_layer.add_child(_mortality_detail)
		_crosshair_mark = _crosshair()
		_hud_layer.add_child(_crosshair_mark)
		add_child(_hud_layer)

	_sync_mortality_overlay(sim)

	var lines: PackedStringArray = PackedStringArray()
	# The Run-over condition first, and in capitals, because it is the only line on the
	# HUD that means the game has stopped — and it names the Wave reached, which is the
	# whole of the score at this milestone.
	if sim.query_run_is_over():
		lines.append("THE NEST HAS FALLEN — reached wave %d" % sim.query_wave_number())
	lines.append_array(_telegraph_lines(sim))
	lines.append_array(_breach_opening_lines(sim))
	# The one line that makes the opening teach itself, in both HUDs: the brief is what a
	# player reads, and the wall is everything the HUD could say, so it cannot be missing
	# from the wall. Empty once the first Delivery has landed, and an empty line is not
	# appended.
	var objective: String = Objective.line(sim, VIEWED_PLAYER)
	if not objective.is_empty():
		lines.append(objective)
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

	_hud_full = "\n".join(lines)
	_hud_brief = "\n".join(_brief_lines(sim))
	_hud.text = _hud_full if _hud_detailed else _hud_brief
	_sync_picker(sim)


## The Machine picker: a cell per Machine and one for the Belt tool, along the bottom of the
## screen, with the icon of what each Machine makes, the key that reaches it, what it costs
## and whether a Delivery still has it locked.
##
## **Machine selection used to be blind mouse-wheeling** through a list with the name in a
## line of text, which meant a player hunting for the Smelter scrolled until the word
## changed. A row of pictures is the fix, and the pictures already existed — #20 generated
## ten Item icons and nothing used one.
##
## A Machine's glyph is **the Item its Recipe makes**, so a Smelter shows an ingot. That is
## the thing a player is actually hunting for, and it means a Machine added as a row gets a
## picture without anybody drawing one. A Machine that makes no Item — a Turret, a generator,
## a Silo — has no glyph and reads by its name, which is honest: there is no picture of
## damage.
##
## Rebuilt only when the definition set changes, repainted every frame. The nodes are a
## handful and the Machine list is ten long, so this is the one place in the view where a
## node per thing is the right shape.
func _sync_picker(sim: Simulation) -> void:
	var definitions: Definitions = sim.query_definitions()
	if _picker == null:
		_picker = HBoxContainer.new()
		_picker.add_theme_constant_override("separation", 6)
		_picker.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		_picker.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_picker.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_picker.offset_bottom = -PICKER_MARGIN_PIXELS
		_hud_layer.add_child(_picker)

	if _picker_built_for != sim.query_definition_generation():
		_build_picker_cells(sim, definitions)
		_picker_built_for = sim.query_definition_generation()

	# What is in hand, what the Run has earned, and what it should do next — all three every
	# frame, all three state, and none of them remembered here.
	_picker_selected = (
		definitions.machine_count() if sim.query_player_is_laying_belt(VIEWED_PLAYER)
		else sim.query_player_selected_machine_index(VIEWED_PLAYER)
	)
	var next_machine: int = Objective.pointed_at(sim, VIEWED_PLAYER)
	_picker_next = -1
	for cell_index: int in range(_picker_cells.size()):
		var machine_index: int = _picker_machines[cell_index]
		var locked: bool = (
			machine_index < definitions.machine_count()
			and not sim.query_machine_is_unlocked(machine_index)
		)
		_picker_locked[cell_index] = 1 if locked else 0
		if machine_index == next_machine:
			_picker_next = cell_index
		var cell: PanelContainer = _picker_cells[cell_index]
		cell.modulate = PICKER_LOCKED_TINT if locked else Color.WHITE
		# Selected beats next, and the comment on `PICKER_NEXT_EDGE` says why a third
		# colour for the two together was tried and thrown away.
		var edge: Color = PICKER_RESTING_EDGE
		if machine_index == _picker_selected:
			edge = PICKER_SELECTED_EDGE
		elif cell_index == _picker_next:
			edge = PICKER_NEXT_EDGE
		_paint_cell_edge(cell, edge)
	_picker.visible = sim.query_player_is_in_build_mode(VIEWED_PLAYER)


## Builds the grid: a column per stage of the chain, an arrow between columns, and the Belt
## tool on the end.
##
## **The order is `BuildChain`'s and nothing here has an opinion about it.** The cells are
## created in key order so `_picker_cells[cell]` means what every accessor below says it
## means, and each is then parented into the column the chain puts it in — so the array is
## the reading order and the scene tree is the layout, from one derivation.
func _build_picker_cells(sim: Simulation, definitions: Definitions) -> void:
	for spare: Node in _picker.get_children():
		_picker.remove_child(spare)
		spare.queue_free()
	_picker_cells.clear()
	_picker_arrows.clear()
	_picker_labels = PackedStringArray()
	_picker_icon_paths = PackedStringArray()
	_picker_input_icon_paths = PackedStringArray()
	_picker_locked = PackedInt64Array()
	_picker_machines = PackedInt64Array()
	_picker_columns = PackedInt64Array()
	_picker_rows = PackedInt64Array()

	var order: PackedInt64Array = BuildChain.order(definitions)
	var columns: PackedInt64Array = BuildChain.column_of(definitions)
	var rows: PackedInt64Array = BuildChain.row_of(definitions)
	var groups: PackedInt64Array = BuildChain.group_of(definitions)

	# One column of the grid per stage, with the arrow that says it feeds the next one.
	# Built before the cells so a cell can be parented straight into its column.
	#
	# **An arrow goes between two columns of the chain and nowhere else.** What a Delivery
	# gates sits in its own columns past the end of it, and a Miner Mk2 is not fed by a
	# Silo — so the gap before that group is a plain separator, and the arrows stop where
	# the statement they make stops being true.
	var deepest: int = -1
	for column: int in columns:
		deepest = maxi(deepest, column)
	var chain_columns: int = 0
	for cell: int in range(order.size()):
		if groups[cell] == BuildChain.GROUP_CHAIN:
			chain_columns = maxi(chain_columns, columns[cell] + 1)
	var stacks: Array[VBoxContainer] = []
	for column: int in range(deepest + 1):
		if column > 0:
			_picker.add_child(
				_feeds_arrow() if column < chain_columns else _picker_separator()
			)
		var stack: VBoxContainer = VBoxContainer.new()
		stack.add_theme_constant_override("separation", 4)
		stack.alignment = BoxContainer.ALIGNMENT_BEGIN
		_picker.add_child(stack)
		stacks.append(stack)

	for cell: int in range(order.size()):
		var machine: MachineDefinition = definitions.machine_at(order[cell])
		_add_picker_cell(
			stacks[columns[cell]],
			BuildChain.key_label(cell),
			machine.display_name,
			_cost_text(machine),
			_input_icon_path_for(definitions, machine),
			_icon_path_for(definitions, machine),
			_what_it_makes(definitions, machine)
		)
		_picker_machines.append(order[cell])
		_picker_columns.append(columns[cell])
		_picker_rows.append(rows[cell])

	# The Belt, last and apart, because it is not a Machine: no row in
	# `content/machines.csv`, no Recipe, and its own key. It does have a price since #47, and
	# the cell quotes it **per tile** rather than for a route, because a cell is about the tool
	# and the route line above is about the drag.
	#
	# It gets its own column rather than joining the last stage: a Belt is what *connects* two
	# stages rather than being one, so standing it under the Turret would be the one false
	# statement in a grid whose whole job is which thing feeds which.
	var apart: VBoxContainer = VBoxContainer.new()
	apart.add_theme_constant_override("separation", 4)
	apart.alignment = BoxContainer.ALIGNMENT_BEGIN
	_picker.add_child(_picker_separator())
	_picker.add_child(apart)
	_add_picker_cell(
		apart,
		"C",
		"Belt",
		"%s / tile" % _bill_text(
			definitions.structure_cost_items(Definitions.STRUCTURE_BELT),
			definitions.structure_cost_counts(Definitions.STRUCTURE_BELT)
		),
		"",
		"",
		"joins them up"
	)
	_picker_machines.append(definitions.machine_count())
	_picker_columns.append(deepest + 1)
	_picker_rows.append(0)


## The arrow between two columns of the chain: this stage feeds the next one.
##
## Pinned to the **top** of the row rather than centred in it, because the row it is a
## statement about is the main line and the main line is row 0. Centred, it floats between
## the two rows and reads as pointing at neither.
func _feeds_arrow() -> Control:
	var arrow: Label = Label.new()
	arrow.text = PICKER_FEEDS_ARROW
	arrow.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	arrow.custom_minimum_size = Vector2(PICKER_ARROW_PIXELS, PICKER_ICON_PIXELS)
	arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_picker_arrows.append(arrow)
	return arrow


## The gap before a group the chain does not feed. Blank, and wider than an arrow: what
## separates the Factory from what a Delivery gates is that there is no relationship at all.
func _picker_separator() -> Control:
	var gap: Control = Control.new()
	gap.custom_minimum_size = Vector2(PICKER_SEPARATOR_PIXELS, 0.0)
	return gap


## What a Machine costs, in the `item:count` form its row is written in. "free" where the
## column is empty, because a blank cell reads as a bug.
func _cost_text(machine: MachineDefinition) -> String:
	return _bill_text(machine.build_cost_items, machine.build_cost_counts)


## A bill of Items as one line. "free" for an empty one, because a blank cell reads as a bug —
## and a Belt, a Wall and a Machine all read their price through here, so the three cannot come
## to word the same thing differently.
func _bill_text(items: PackedStringArray, counts: PackedInt64Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for slot: int in range(items.size()):
		parts.append("%s %d" % [items[slot], counts[slot]])
	return "free" if parts.is_empty() else ", ".join(parts)


## The icon of the first Item a Machine's Recipe produces, or "" for one that produces none.
func _icon_path_for(definitions: Definitions, machine: MachineDefinition) -> String:
	var recipe: RecipeDefinition = definitions.recipe(machine.recipe_id)
	if recipe == null or recipe.output_count() == 0:
		return ""
	return _icon_of(definitions, recipe.output_item(0))


## The icon of the first Item a Machine's Recipe consumes, or "" for one that consumes none.
##
## **#53: a cell says what the Machine eats as well as what it makes.** #36 drew the output
## alone, which is half the information — a player hunting for "the thing that turns ore into
## plate" is looking for the ore. A Miner has nothing here because its input is the ground,
## which is not an Item and never will be, and that reads as the honest absence a Machine with
## no generated body already reads as.
func _input_icon_path_for(definitions: Definitions, machine: MachineDefinition) -> String:
	var recipe: RecipeDefinition = definitions.recipe(machine.recipe_id)
	if recipe == null or recipe.input_count() == 0:
		return ""
	return _icon_of(definitions, recipe.input_item(0))


## The icon of one Item, or "" where the generated set has no picture of it.
##
## **Public since #59, because it is the one authority on whether an Item has a picture and
## a test had to be able to ask it.** `tests/cases/test_item_icons.gd` walks every Item the
## Recipes intern through this very function, so the check and the hotbar cannot come to
## disagree about what resolves — the arrangement `query_build_refusal` has with the
## hologram. Static because it reads nothing but the definition set and the constant.
##
## `ResourceLoader.exists` rather than `FileAccess.file_exists` is deliberate and is what
## makes the check stronger than a Python one could be: a committed `.png` with no committed
## `.import` sidecar beside it is **on disk and invisible to the game**, which is exactly the
## blank cell this is about.
static func icon_path_for_item(definitions: Definitions, item: int) -> String:
	var item_id: String = definitions.item_id(item)
	if item_id.is_empty():
		return ""
	var path: String = "%s/%s.png" % [ICON_DIRECTORY, item_id]
	return path if ResourceLoader.exists(path) else ""


func _icon_of(definitions: Definitions, item: int) -> String:
	return icon_path_for_item(definitions, item)


## What a Machine makes, in words, for the cell of one whose product is not an Item.
##
## A Turret, a generator and a Silo all answer `produces_no_items()`, and there is no picture
## of damage — so the cell says the word instead. **It names the Role rather than the row**,
## which is the rule `Objective` keeps: the Role is a column in `content/machines.csv` and a
## word for it is a sentence about a fact, where naming `mg_turret_mk1` would be a second
## content table written in GDScript.
##
## A Machine that does make an Item says the Item, which is what the icon beside it already
## shows — so a missing picture degrades to a name rather than to nothing.
func _what_it_makes(definitions: Definitions, machine: MachineDefinition) -> String:
	var recipe: RecipeDefinition = definitions.recipe(machine.recipe_id)
	if recipe != null and recipe.output_count() > 0:
		return definitions.item_id(recipe.output_item(0)).replace("_", " ")
	if machine.is_generator():
		return "power"
	if machine.is_silo():
		return "charges"
	if machine.is_turret():
		return "repair" if machine.heals() else "damage"
	return ""


## One cell: the key that reaches it, what it is, what it eats, what it makes, and what it
## costs. Parented into the column of the grid the chain puts it in.
func _add_picker_cell(
	stack: VBoxContainer,
	key: String,
	name: String,
	cost: String,
	input_icon_path: String,
	icon_path: String,
	makes: String
) -> void:
	var cell: PanelContainer = PanelContainer.new()
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	cell.add_child(column)

	# The icon row: what it eats on the left, what it makes on the right. The slots are
	# there whether or not there is a picture to put in them — a render showed why in #36:
	# without them the cells with a picture are taller than the cells without, and a row of
	# hotbar cells whose captions sit at six different heights reads as broken.
	var pictures: HBoxContainer = HBoxContainer.new()
	pictures.add_theme_constant_override("separation", 0)
	pictures.alignment = BoxContainer.ALIGNMENT_CENTER
	pictures.add_child(_picker_picture(input_icon_path))
	# **The same arrow inside the cell as between the columns, and a render is why.** The
	# Ammo Press makes Ammunition and the MG Turret eats it, so when #53 rendered them the
	# two cells carried one identical glyph each with nothing to say which side of the
	# transformation it was on — `iron_plate` had no icon then, so the Press's other slot
	# was empty. #59 filled it and the arrow is still what the cell needs: eats on the left,
	# makes on the right, and two pictures side by side say even less than one without it.
	var through: Label = Label.new()
	through.text = PICKER_FEEDS_ARROW
	through.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	through.custom_minimum_size = Vector2(PICKER_ARROW_PIXELS, 0.0)
	through.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pictures.add_child(through)
	pictures.add_child(_picker_picture(icon_path))
	column.add_child(pictures)

	var caption: Label = Label.new()
	caption.text = "[%s] %s\n%s\n%s" % [key, name, makes, cost]
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(caption)

	_paint_cell_edge(cell, PICKER_RESTING_EDGE)
	stack.add_child(cell)
	_picker_cells.append(cell)
	_picker_labels.append(caption.text)
	_picker_icon_paths.append(icon_path)
	_picker_input_icon_paths.append(input_icon_path)
	_picker_locked.append(0)


## Repaints one cell's border, reusing the box it already owns rather than building a new
## one every frame for ten cells.
func _paint_cell_edge(cell: PanelContainer, edge: Color) -> void:
	var box: StyleBoxFlat = cell.get_theme_stylebox("panel") as StyleBoxFlat
	if box == null or not box.has_meta(&"picker_cell"):
		box = StyleBoxFlat.new()
		box.set_meta(&"picker_cell", true)
		box.bg_color = PICKER_BACKING
		box.set_border_width_all(PICKER_BORDER_PIXELS)
		box.set_corner_radius_all(3)
		box.set_content_margin_all(6.0)
		cell.add_theme_stylebox_override("panel", box)
	box.border_color = edge


## One icon slot. Full size: a render of the half-size version showed two 20-pixel glyphs
## reading as smudges under a caption three lines long, and a cell is already as wide as
## "[6] Steam Boiler Mk1" — so there was never any width to save.
func _picker_picture(icon_path: String) -> TextureRect:
	var picture: TextureRect = TextureRect.new()
	if not icon_path.is_empty():
		picture.texture = load(icon_path)
	picture.custom_minimum_size = Vector2(PICKER_ICON_PIXELS, PICKER_ICON_PIXELS)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return picture


## How many cells the picker has: one per Machine, plus the Belt tool. For the smoke test.
func machine_picker_cell_count() -> int:
	return _picker_cells.size()


## Which Machine a cell is about, by definition index — or `machine_count()` for the Belt's
## cell, which is the convention the Build Gun's own selection already uses. For the smoke
## test, and the inverse of `BuildChain.cell_of`.
##
## **Cells are numbered in chain order since #53**, not in the Machine table's id order, so
## this is how a test asks about a particular Machine's cell without restating the order.
func machine_picker_machine(cell: int) -> int:
	if cell < 0 or cell >= _picker_machines.size():
		return -1
	return _picker_machines[cell]


## Which column of the grid a cell is drawn in: how many crafts deep the chain it is on runs.
## For the smoke test.
func machine_picker_column(cell: int) -> int:
	if cell < 0 or cell >= _picker_columns.size():
		return -1
	return _picker_columns[cell]


## Which row within its column a cell is drawn on. Row 0 is the main line. For the smoke test.
func machine_picker_row(cell: int) -> int:
	if cell < 0 or cell >= _picker_rows.size():
		return -1
	return _picker_rows[cell]


## Whether a cell is the one the objective line is talking about. For the smoke test.
func machine_picker_is_next(cell: int) -> bool:
	return cell >= 0 and cell == _picker_next


## Which cell the objective line is talking about, or -1 for a step that is not about placing
## anything. For the smoke test.
func machine_picker_next_cell() -> int:
	return _picker_next


## How many "feeds" arrows stand between the columns: one per gap, so one fewer than the
## number of stages the chain has. For the smoke test.
func machine_picker_arrow_count() -> int:
	return _picker_arrows.size()


## The icon of what a cell's Machine eats, or "" where its input is the ground. For the
## smoke test.
func machine_picker_input_icon_path(cell: int) -> String:
	if cell < 0 or cell >= _picker_input_icon_paths.size():
		return ""
	return _picker_input_icon_paths[cell]


## What a cell says: its key, its name and what it costs. For the smoke test.
func machine_picker_label(cell: int) -> String:
	if cell < 0 or cell >= _picker_labels.size():
		return ""
	return _picker_labels[cell]


## The icon a cell carries, or "" where the Machine makes no Item. For the smoke test.
func machine_picker_icon_path(cell: int) -> String:
	if cell < 0 or cell >= _picker_icon_paths.size():
		return ""
	return _picker_icon_paths[cell]


## Whether a Delivery still has a cell's Machine locked. For the smoke test.
func machine_picker_is_locked(cell: int) -> bool:
	if cell < 0 or cell >= _picker_locked.size():
		return false
	return _picker_locked[cell] != 0


## Which cell is in the player's hands — a Machine's index, or the Belt cell past the end of
## the Machine list. For the smoke test.
func machine_picker_selected() -> int:
	return _picker_selected


## The HUD a player actually reads: what they are doing, what is coming, and what is wrong.
##
## **Six things, in the order a player needs them**, against the fifty-three the full HUD
## assembles. The test of each line is whether it changes what the player does in the next
## few seconds — which is why the Wave banner and the objective are at the top, why the
## Machines in trouble are named and the healthy ones are not counted at all, and why the
## Gear table, the Silo dial, the Nest's store and the per-Item totals are behind the key.
##
## Nothing here is a second copy of a decision. The urgent banners, the build-gun lines and
## the route line are the same helpers the full HUD calls; the trouble summary is a *shorter
## sentence about the same queries*, not a reimplementation of the long one — it names ids
## and states, where the full list adds buffers, Heat, magazines and health.
func _brief_lines(sim: Simulation) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	if sim.query_run_is_over():
		lines.append("THE NEST HAS FALLEN — reached wave %d" % sim.query_wave_number())
	lines.append_array(_telegraph_lines(sim))
	lines.append_array(_breach_opening_lines(sim))

	# The one line that makes the opening teach itself. Empty once it has, and an empty
	# line is not appended — a blank row at the top of the screen is one more thing to read.
	var objective: String = Objective.line(sim, VIEWED_PLAYER)
	if not objective.is_empty():
		lines.append(objective)

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
	lines.append(
		"power %d/%d kW — %d%%"
		% [
			sim.query_power_supply_kw(),
			sim.query_power_demand_kw(),
			roundi(Fixed.to_float(sim.query_power_ratio()) * 100.0),
		]
	)
	lines.append_array(_build_gun_lines(sim))
	lines.append_array(_trouble_lines(sim))
	lines.append("[H] details")
	return lines


## What is wrong with the Factory, in as few words as will still get somebody to the right
## Machine: the ones in trouble by id and state, then a count of the rest.
##
## **Triage is not silence.** The whole reason the wall existed is that a player mid-Wave has
## to know which Machine is in trouble; what was wrong with it was the forty lines around
## that one. Damaged outranks starved outranks throttled, which is the same order the full
## list uses and for the same reason — they are three different fixes.
func _trouble_lines(sim: Simulation) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var named: PackedStringArray = PackedStringArray()
	var unnamed: int = 0
	for index: int in range(sim.query_machine_count()):
		var state: String = ""
		if sim.query_machine_health(index) < sim.query_machine_max_health(index):
			state = "DAMAGED"
		elif sim.query_machine_is_starved(index):
			state = "starved"
		elif sim.query_machine_is_throttled(index):
			state = "throttled"
		elif sim.query_machine_is_turret(index) and sim.query_turret_ammunition(index) == 0:
			state = "DRY"
		if state.is_empty():
			continue
		if named.size() >= BRIEF_MACHINES_LISTED:
			unnamed += 1
			continue
		named.append("%s %s" % [sim.query_machine_id(index), state])

	var dangling: int = dangling_marker_count()
	# A branch is the one thing in a Factory whose trouble cannot be read off its own Machine:
	# `query_machine_is_starved` has nothing to say about a Smelter whose *output* has nowhere
	# to go, and two Belts off one Machine look identical from above whether they are sharing
	# or one of them is stopped. The counts come off the marks rather than being worked out a
	# second way here, exactly as the dangling-ends clause beside them does — so the post in
	# the world and the number on screen are one decision, and the division of labour is the
	# one #36 settled: the mark says *where*, the line says *how many*.
	var blocked: int = blocked_branch_marker_count()
	var banking: int = banking_marker_count()
	if named.is_empty() and dangling == 0 and blocked == 0 and banking == 0:
		return lines

	var sentence: String = ", ".join(named) if not named.is_empty() else "all machines fed"
	if unnamed > 0:
		sentence += " and %d more" % unnamed
	if dangling > 0:
		sentence += " — %d belt end%s lead nowhere" % [dangling, "" if dangling == 1 else "s"]
	if blocked > 0:
		sentence += " — %d branch%s blocked" % [blocked, "" if blocked == 1 else "es"]
	# Said in the same breath because it is the answer to the alarm the blocked branches
	# raise: nothing is being destroyed, the Machine's output buffer is uncapped and the
	# surplus is in it. A player who did not know that would tear the line down.
	if banking > 0:
		sentence += " — %d split%s banking the surplus" % [banking, "" if banking == 1 else "s"]
	lines.append(sentence)
	lines.append_array(_dock_advice_lines(sim))
	return lines


## What would make a Belt that is up against a Machine actually connect, one line per distinct
## reason.
##
## **The count stays on the line above and the advice is its own**, which is #36's division of
## labour kept: the red post says *where*, the count says *how many*, and this says *what to
## do*. A dangling end with open ground beyond it needs no sentence — it needs a longer Belt,
## and the post already says so. The ones worth a line are the ends standing against a
## Machine's wall that the Machine will not take goods through, because those are the ones a
## player reads as a bug (#56): the line is the right length and pointed the right way, and
## nothing on screen said the Machine is facing the wrong direction.
##
## Distinct reasons rather than one line per Belt, because the mistake is almost always made
## at both ends of the same line at once — a Smelter stood square in an east-to-west line
## connects neither of its Belts — and two identical sentences would be the wall this HUD is
## trying to stop being.
func _dock_advice_lines(sim: Simulation) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var seen: PackedInt64Array = PackedInt64Array()
	for index: int in range(sim.query_belt_count()):
		for refusal: int in [
			sim.query_belt_start_dock_refusal(index),
			sim.query_belt_end_dock_refusal(index),
		]:
			if refusal == Simulation.Refusal.NONE or seen.has(refusal):
				continue
			seen.append(refusal)
			lines.append("belt will not dock: %s" % BuildGun.refusal_text(refusal))
	return lines


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
	lines.append("   %s" % _telegraph_composition(sim))
	return lines


## What the telegraphed Wave is made of, as a line of text — "6 crawlers, 2 breakers".
##
## **The legible half of #34, and the reason it is on the Telegraph rather than anywhere else.**
## A Breaker now marches the same road as everything else and turns on the Factory once it is
## inside the perimeter, which is a lesson a player can act on — *if* they knew a Breaker was
## in this Wave while there was still time to go and stand over the Smelters. So the warning
## names its tiers. Six Crawlers is a line to hold; six Crawlers and two Breakers is a reason
## to be somewhere else.
##
## Walked in `EnemyKind` order rather than in the Wave table's, so the same Wave reads the same
## way every time and a player learns where to look rather than re-reading the line. A tier the
## Heat has not reached contributes nothing and is not named, which is what makes the arrival of
## a new word on this line the event it should be.
func _telegraph_composition(sim: Simulation) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for kind: int in range(EnemyKind.KIND_NAMES.size()):
		var count: int = sim.query_telegraphed_wave_count_of_kind(kind)
		if count <= 0:
			continue
		parts.append("%d %s%s" % [count, EnemyKind.name_of(kind), "s" if count != 1 else ""])
	if parts.is_empty():
		return "nothing the Heat has unlocked yet"
	return ", ".join(parts)


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
	# **The collapse (#54), and it is laid on here for the reason the dip is.** A player who
	# has been killed or Downed goes over, and `query_player_camera_height_metres` deliberately
	# does not know about it: a body going limp must not move where a round goes, which is the
	# same test the bob and the lean are decided by. Subtracted, like the dip, because both are
	# quoted as positive magnitudes.
	var collapse: float = Fixed.to_float(
		sim.query_player_view_collapse_metres(VIEWED_PLAYER)
	)
	# The lateral bob is in the player's own frame, so it goes along their right vector.
	var right: Vector3 = Vector3(cos(yaw), 0.0, -sin(yaw))

	_camera.position = (
		Vector3(
			Fixed.to_float(ground.x),
			Fixed.to_float(sim.query_player_camera_height_metres(VIEWED_PLAYER)),
			Fixed.to_float(ground.z)
		)
		+ Vector3(0.0, bob_up - dip - collapse, 0.0)
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
		# A bank to the player's right is a negative roll about Godot's forward axis. The
		# collapse's list uses the same sign convention as the lean's, so the two simply add.
		-(
			Fixed.to_float(sim.query_player_view_roll_turns(VIEWED_PLAYER))
			+ Fixed.to_float(sim.query_player_view_collapse_roll_turns(VIEWED_PLAYER))
		) * TAU
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


# ── The death overlay ─────────────────────────────────────────────────────────

## Builds the tint and the two captions, once. See the `#54` note beside `DEAD_TINT` for why
## each of them is shaped the way it is.
func _build_mortality_overlay() -> void:
	_mortality_tint = ColorRect.new()
	_mortality_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mortality_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mortality_tint.color = DEAD_TINT
	_mortality_tint.visible = false

	_mortality_caption = _mortality_line(
		MORTALITY_CAPTION_FONT_PIXELS, MORTALITY_CAPTION_COLOUR
	)
	_mortality_detail = _mortality_line(
		MORTALITY_DETAIL_FONT_PIXELS, MORTALITY_DETAIL_COLOUR
	)


## One centred line of the overlay's type. Where it sits vertically is set every frame by
## `_sync_mortality_overlay`, because it depends on the size of the viewport.
func _mortality_line(size: int, colour: Color) -> Label:
	var line: Label = Label.new()
	line.set_anchors_preset(Control.PRESET_FULL_RECT)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_theme_font_size_override("font_size", size)
	line.add_theme_color_override("font_color", colour)
	# A dark outline, because the caption is drawn over whatever killed the player and a pale
	# word over a pale Machine is a word nobody reads.
	line.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	line.add_theme_constant_override("outline_size", maxi(size / 8, 2))
	line.visible = false
	return line


## Shows the player what has happened to them, out of three queries and nothing remembered.
##
## **The blend does all the work.** `query_player_collapse_blend` is 0 on your feet, rises to
## its resting value as a body goes over, and runs back to 0 as one gets up — so the tint
## fades in with the fall and out with the rise, and the whole overlay disappears by itself
## the moment a player is upright again. There is no state here and no tween: a frame that
## stepped nothing draws the same thing twice, which is the rule the scanner sweep and the
## view model's clip time already keep.
func _sync_mortality_overlay(sim: Simulation) -> void:
	var blend: float = Fixed.to_float(sim.query_player_collapse_blend(VIEWED_PLAYER))
	var downed: bool = sim.query_player_is_downed(VIEWED_PLAYER)
	var dead: bool = sim.query_player_is_dead(VIEWED_PLAYER)
	var showing: bool = blend > 0.0

	# **The crosshair goes with them, and a render is why.** It is an aiming reticle and the
	# Build Gun aims down the middle of the view — but a player who has been killed aims at
	# nothing, every intent they could send is refused by `_act_refusal`, and the first render
	# of this gesture had a crisp white cross sitting in the middle of a body on the deck. It
	# comes back on the tick they are upright, off the same number as everything else here.
	if _crosshair_mark != null:
		_crosshair_mark.visible = not showing

	_mortality_tint.visible = showing
	_mortality_caption.visible = showing
	_mortality_detail.visible = showing
	if not showing:
		# Cleared rather than left stale, so `mortality_caption` never reports a word about a
		# state the player is no longer in.
		_mortality_caption.text = ""
		_mortality_detail.text = ""
		return

	var tint: Color = DOWNED_TINT if downed else DEAD_TINT
	_mortality_tint.color = Color(tint.r, tint.g, tint.b, tint.a * blend)

	var caption: String = ""
	var detail: String = ""
	if downed:
		caption = "DOWN"
		detail = (
			"bleeding out — %ds for a teammate to reach you"
			% [
				sim.query_player_downed_ticks_remaining(VIEWED_PLAYER)
				/ Simulation.TICKS_PER_SECOND
			]
		)
	elif dead:
		caption = "DEAD"
		detail = (
			"back at the Nest in %ds — you lose nothing but the time"
			% [
				sim.query_player_respawn_ticks_remaining(VIEWED_PLAYER)
				/ Simulation.TICKS_PER_SECOND
			]
		)
	else:
		# Alive, and still part way down: this is the rise. **The one acknowledgement that a
		# respawn happened** — before #54 a player appeared on the Nest's crown mid-stride with
		# nothing on either side of the cut.
		caption = "BACK AT THE NEST"
		detail = ""

	_mortality_caption.text = caption
	_mortality_detail.text = detail

	# Both labels fill the screen and centre their one line in it, so **shifting `offset_top`
	# by N moves the line by N/2** — the rect loses N off the top and the centre of what is
	# left moves half of that. The first render of this overlay got that wrong and drew the
	# countdown straight through the bottom of the word above it, which is #41's lesson in
	# another costume: a mark whose position is arithmetic nobody looked at.
	var drop: float = _mortality_tint.size.y * MORTALITY_CAPTION_DROP
	var apart: float = float(MORTALITY_CAPTION_FONT_PIXELS + MORTALITY_LINE_GAP_PIXELS)
	_mortality_caption.offset_top = drop
	_mortality_detail.offset_top = drop + apart * 2.0


## What the death overlay is saying, or `""` when it is not up. For the suite: the claim #54
## is about is that a player can tell at a glance, and the glance is this word.
func mortality_caption() -> String:
	return "" if _mortality_caption == null else _mortality_caption.text


## The line under it — the countdown and what it costs — or `""`.
func mortality_detail() -> String:
	return "" if _mortality_detail == null else _mortality_detail.text


## How far the screen is tinted, in [0, 1], and whether the overlay is up at all.
func mortality_tint_alpha() -> float:
	return 0.0 if _mortality_tint == null or not _mortality_tint.visible \
		else _mortality_tint.color.a


func mortality_overlay_is_up() -> bool:
	return _mortality_tint != null and _mortality_tint.visible


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

	# **The panel describes the tool in hand, and nothing else.** #67: both of the lines
	# below were about the Machine on the gun whichever tool was out, so a player dragging a
	# Belt read `build gun: miner_mk1 facing 0` over `aimed at -6, 10 — cannot build there`
	# — a Machine nobody is placing, a rotation nothing will be turned by, and a refusal
	# about ground the player is not asking about, sitting directly above the route line and
	# reading as if it were the route's. `_belt_route_lines` answers the question the Belt
	# tool actually asks, so these two stand down for it rather than talking over it.
	if sim.query_player_is_laying_belt(VIEWED_PLAYER):
		lines.append("build gun: belt")
		lines.append_array(_belt_route_lines(sim, BuildGun.aimed_tile(sim, VIEWED_PLAYER)))
		lines.append_array(_carrying_lines(sim))
		return lines

	lines.append(
		"build gun: %s facing %d" % ["nothing" if selected.is_empty() else selected, rotation]
	)

	# The tile the Machine would land on rather than the one under the crosshair, because
	# for a Miner those are different since #42 and the useful one is the first.
	var machine: int = sim.query_player_selected_machine_index(VIEWED_PLAYER)
	var where: BuildGun.Placement = BuildGun.placement(sim, VIEWED_PLAYER, machine, rotation)
	var tile: Vector3i = where.tile
	# The same door the hologram and the click go through, so the panel cannot report a
	# tile as clear while the Build Gun is on the player's back.
	var refusal: int = BuildGun.build_refusal(
		sim,
		VIEWED_PLAYER,
		sim.query_player_is_in_build_mode(VIEWED_PLAYER),
		machine,
		tile,
		rotation
	)
	# **The Simulation's refusal outranks the aim's**, and the locked Machine is why. Being
	# locked is a fact about what is on the gun rather than about the ground, so a player
	# told "no ore in range" would walk to a Node and still not be able to build — the same
	# argument `_build_refusal` makes for putting `CONTENT_IS_LOCKED` before the tile. An
	# aim reason is therefore what is said when the Simulation would otherwise accept.
	if refusal != Simulation.Refusal.NONE:
		lines.append("aimed at %d, %d — %s" % [tile.x, tile.z, BuildGun.refusal_text(refusal)])
	elif where.aim != BuildGun.Aim.ON_TARGET:
		lines.append("aimed at %d, %d — %s" % [tile.x, tile.z, BuildGun.aim_text(where.aim)])
	else:
		lines.append(
			"aimed at %d, %d — clear%s"
			% [tile.x, tile.z, " (snapped to the Node)" if where.snapped else ""]
		)
	lines.append_array(_carrying_lines(sim))
	return lines


## What the player is holding and how they are moving — the tail of the Build Gun panel,
## which is the same under either tool and is therefore shared by both arms above rather
## than written twice.
func _carrying_lines(sim: Simulation) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var carried: PackedStringArray = PackedStringArray()
	for item_id: String in sim.query_player_items(VIEWED_PLAYER):
		carried.append("%s %d" % [item_id, sim.query_player_item(VIEWED_PLAYER, item_id)])
	lines.append("carrying: %s" % ("nothing" if carried.is_empty() else ", ".join(carried)))

	if sim.query_player_is_surveying(VIEWED_PLAYER):
		lines.append("survey view")
	if sim.query_player_is_sprinting(VIEWED_PLAYER):
		lines.append("sprinting")

	return lines


## The route the drag in flight would lay: how long it is, what it costs, and why it would be
## refused — all three **before the button comes up**, which is the whole point of the
## projection being a projection.
##
## Empty unless the Belt tool is out, because a line about a route nobody is drawing is one
## more line of the wall this HUD is trying to stop being.
##
## **The cost is the bill for the whole route, not the per-tile price**, because the per-tile
## price is a number a player would have to multiply by the length themselves while holding a
## mouse button down. It comes out of `query_belt_route_cost_*`, which is the same per-tile row
## of `content/structures.csv` the Simulation charges from, so the line cannot quote one price
## and the drag spend another. "free" where the table prices a Belt at nothing, which is what a
## Run with no structures table does.
func _belt_route_lines(sim: Simulation, aimed: Vector3i) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	if not sim.query_player_is_laying_belt(VIEWED_PLAYER):
		return lines

	var from_tile: Vector3i = _belt_drag_anchor if _belt_drag_active else aimed
	var length: int = maxi(
		BeltRoute.length_tiles(from_tile, aimed, _belt_drag_corner_axis), 1
	)
	var refusal: int = sim.query_belt_route_refusal(
		VIEWED_PLAYER, from_tile, aimed, _belt_drag_corner_axis
	)
	var lays: bool = refusal == Simulation.Refusal.NONE
	var verdict: String = "clear" if lays else BuildGun.refusal_text(refusal)
	# **The lead clause reads off the same refusal the verdict does**, because a line cannot
	# mean "release it" and "cannot build there" at once and #67's shot had one that said
	# both. The verdict was right and the invitation was printed unconditionally beside it,
	# so the invitation is the half that moves — and it moves off the one function the
	# release itself goes through, which is the same bargain the preview's colour strikes
	# three functions down.
	var lead: String = "drag to route, right click turns the corner"
	if _belt_drag_active:
		lead = "release to lay" if lays else "will not lay"
	lines.append(
		"belt: %s — %d tiles — %s — %s"
		% [lead, length, _route_cost_text(sim, from_tile, aimed), verdict]
	)
	# And why its ends would not dock, which is advice rather than a verdict: the route lays
	# either way (see `query_belt_route_end_dock_refusal`), so this is a second line and not
	# part of the one above. #56 — the docking rule has been enforced since #47 and the arrows
	# drawn since #36, and the thing never said was what to do about a line that will not
	# connect.
	var advice: PackedStringArray = PackedStringArray()
	var at_start: int = sim.query_belt_route_start_dock_refusal(
		VIEWED_PLAYER, from_tile, aimed, _belt_drag_corner_axis
	)
	if at_start != Simulation.Refusal.NONE:
		advice.append("nothing will feed it — %s" % BuildGun.refusal_text(at_start))
	var at_end: int = sim.query_belt_route_end_dock_refusal(
		VIEWED_PLAYER, from_tile, aimed, _belt_drag_corner_axis
	)
	if at_end != Simulation.Refusal.NONE:
		advice.append("it will not hand over — %s" % BuildGun.refusal_text(at_end))
	for sentence: String in advice:
		lines.append("  %s" % sentence)
	return lines


## What the route in flight would cost, in the `item count` form the picker's cells use.
## "free" where it costs nothing, because a blank reads as a bug.
func _route_cost_text(sim: Simulation, from_tile: Vector3i, aimed: Vector3i) -> String:
	var items: PackedStringArray = sim.query_belt_route_cost_items(
		VIEWED_PLAYER, from_tile, aimed, _belt_drag_corner_axis
	)
	var counts: PackedInt64Array = sim.query_belt_route_cost_counts(
		VIEWED_PLAYER, from_tile, aimed, _belt_drag_corner_axis
	)
	return _bill_text(items, counts)


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
##
## The ground is `game/ground.gdshader` over a plane that runs well past the buildable
## Map, and the yard standing on it is `SetDressing`. Both were placeholders and both
## read as placeholders: a Factory on a flat sheet with a grid on it is good models on
## graph paper, and the world stopping dead at the Map's edge is the clearest possible
## statement that there is nothing here.
func _sync_scenery(sim: Simulation) -> void:
	if _set_dressing != null:
		_set_dressing.sync(sim)
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
	world.ambient_light_energy = 1.7
	world.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	# Filmic, because the sky is bright and the Machines are dark and a linear curve
	# cannot hold both — without it the ground blows out to white while a Smelter stays a
	# silhouette. The exposure sits a little under one so the ochre keeps its colour.
	world.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.tonemap_exposure = 1.08
	world.tonemap_white = 2.0

	# Contact shadow in the crevices of a body, which is most of what makes rivets,
	# gauges and frames read as parts rather than as texture.
	#
	# **The radius came down from 0.9 m, and that is what seats a prop on the ground.**
	# At the old radius a crate darkened the metre of yard around it evenly and did not
	# darken the centimetre *under* it any more than the rest, so it read as hovering —
	# the exact complaint. A tighter radius with more detail puts a hard line where a
	# thing meets the floor, which is what the eye reads as contact. `ssao_detail` is the
	# half-resolution pass that recovers the fine end a small radius would otherwise lose.
	world.ssao_enabled = true
	world.ssao_radius = 0.38
	world.ssao_intensity = 2.4
	world.ssao_power = 1.7
	world.ssao_detail = 1.1
	world.ssao_horizon = 0.08
	world.ssao_sharpness = 0.98

	# The lamps in the yard are lit by an emission map and nothing else, and emission
	# without bloom is a bright texel rather than a light. Threshold high and intensity
	# low: this is a lamp reading as lit, not a haze over the whole frame.
	world.glow_enabled = true
	world.glow_intensity = 0.55
	world.glow_strength = 1.0
	world.glow_bloom = 0.04
	world.glow_hdr_threshold = 1.25
	world.glow_hdr_scale = 2.4
	world.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	# **Does the Dieselpunk palette survive to the final image?** Filmic tonemapping and a
	# bright ochre sky between them desaturate everything that is not already saturated,
	# and the palette is mostly dark neutrals — cast iron at 0.055, welded steel at 0.14 —
	# so what came out the far end was grey with an ochre cast over it. A little
	# saturation and contrast after the tonemap puts the olive back on a housing and the
	# oxide back on a primer, which is what the palette is for.
	world.adjustment_enabled = true
	world.adjustment_saturation = 1.16
	world.adjustment_contrast = 1.06
	world.adjustment_brightness = 1.0

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
	#
	# **A stronger hour.** It sat at 41 degrees, which is afternoon rather than late
	# afternoon, and 41 degrees throws a shadow about as long as the thing casting it —
	# long enough to see and not long enough to say anything. At 23 degrees a 3 m Machine
	# lays seven metres of shadow across the yard, the lit faces go warm and the shaded
	# ones go to the cool fill, and the time of day becomes something the frame states
	# rather than something it fails to contradict.
	_sun.rotation = Vector3(-0.40, 0.66, 0.0)
	_sun.light_energy = 3.2
	_sun.light_color = Color(1.0, 0.84, 0.63)
	_sun.shadow_enabled = true
	# Not fully black. A Machine in shadow still has to read as that Machine, and a
	# Factory half of which is unreadable at a glance defeats the point of Survey View.
	_sun.shadow_opacity = 0.92
	# **Four splits over 110 m rather than one blend over 160.** A single cascade stretched
	# across the whole draw distance spends most of its resolution on ground nobody is
	# looking at, and what that costs is the near end: the shadow a railing throws on the
	# floor beside it was two texels wide and so was not there. Pulling the far plane in
	# and weighting the split towards the camera puts the resolution where the Factory is,
	# which is the half-metre detail that makes a prop sit on the ground.
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_sun.directional_shadow_max_distance = 110.0
	_sun.directional_shadow_split_1 = 0.045
	_sun.directional_shadow_split_2 = 0.13
	_sun.directional_shadow_split_3 = 0.38
	_sun.directional_shadow_blend_splits = true
	_sun.directional_shadow_fade_start = 0.92
	# Peter-panning is the other half of "props hover": too much normal bias and a
	# shadow detaches from its caster's feet. These are low on purpose, and the pairing
	# with four tight cascades is what lets them be.
	_sun.shadow_normal_bias = 0.9
	_sun.shadow_bias = 0.035
	_sun.shadow_blur = 0.8
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
	var build_extent: float = float(sim.query_grid_half_extent_tiles()) * tile_size
	var span: float = (
		(float(sim.query_grid_half_extent_tiles() + GROUND_APRON_TILES) * 2.0) * tile_size
	)

	_ground = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(span, span)
	# The shader paints the grid from the world position, so the plane needs no UVs and
	# no subdivision — but it does need enough of the frustum not to be culled when a
	# player stands at one corner of it looking at the other.
	_ground.mesh = plane
	_ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ground.material_override = _ground_material(tile_size, build_extent)
	add_child(_ground)

	_set_dressing = SetDressing.new()
	_set_dressing.name = "SetDressing"
	add_child(_set_dressing)
	_set_dressing.sync(sim)


## The ground's material: #20's generated maps blended in world space, with the 2 m grid
## drawn as markings on top of them.
##
## The grid pitch and the Map's extent are **queried, not assumed**. They are the two
## numbers the shader has to agree with the Simulation about — a grid that does not line
## up with the tiles is worse than no grid, and an apron that starts in the wrong place
## tells a player they cannot build where they can.
func _ground_material(tile_size: float, build_extent: float) -> ShaderMaterial:
	var surface: ShaderMaterial = ShaderMaterial.new()
	surface.shader = load("res://game/ground.gdshader") as Shader
	surface.set_shader_parameter(
		"concrete", load("res://assets/generated/textures/poured_concrete.png")
	)
	surface.set_shader_parameter(
		"worn", load("res://assets/generated/textures/rust_pitted_steel.png")
	)
	surface.set_shader_parameter(
		"grime", load("res://assets/generated/textures/soot_brick.png")
	)
	surface.set_shader_parameter("tile_metres", tile_size)
	surface.set_shader_parameter("build_extent_metres", build_extent)
	return surface


## The Build Gun's hologram: the body of the selected Machine, drawn translucent on the
## tile the gun is aimed at, turned by the rotation the player is holding, and coloured by
## whether the Simulation would accept it.
##
## It is the Machine's own body rather than a box because the question a player is asking
## is "will *that* fit there", and a box cannot answer it — a derrick's legs and a boiler's
## drum occupy their footprint very differently.
##
## Everything here is a query. The aim comes from `BuildGun`, which derives it from where
## the Simulation says the camera is; the refusal comes from `BuildGun.build_refusal`, which
## is the same function the click goes through — the Simulation's own rule about the tile,
## plus the one fact that lives on this side of the boundary, which is whether the Build Gun
## is in the player's hands at all. Nothing is remembered between frames, so there is no way
## for the hologram to promise a placement the next click will not make.
func _sync_hologram(sim: Simulation) -> void:
	if _hologram == null:
		_hologram = MeshInstance3D.new()
		var fresh: StandardMaterial3D = StandardMaterial3D.new()
		fresh.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fresh.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_hologram.material_override = fresh
		add_child(_hologram)

	# What the Build Gun would do with a click, asked once and used three times: where the
	# promise stands, whether there is one to draw at all, and what colour it is.
	#
	# **`where.tile` is not the tile under the crosshair.** For a Miner it is the Node the
	# gun snapped to (#42), and `BuildGun.placement` is the same call `PlayerController`
	# puts in the intent — so the hologram is a promise the click keeps. Everything below
	# reads it, the refusal included: asking the Simulation about the tile a player was
	# *pointing* at while drawing the Machine somewhere else is the precise defect this
	# whole arrangement exists to make impossible.
	#
	# `BuildGun.build_refusal` is likewise the same door the click goes through, so the
	# hologram cannot promise a placement the next click will not make — #35's playtest
	# found it still drawn, and still green, with a rifle in frame.
	var rotation: int = sim.query_player_build_rotation(VIEWED_PLAYER)
	var machine: int = sim.query_player_selected_machine_index(VIEWED_PLAYER)
	var where: BuildGun.Placement = BuildGun.placement(sim, VIEWED_PLAYER, machine, rotation)
	var tile: Vector3i = where.tile
	var refusal: int = BuildGun.build_refusal(
		sim,
		VIEWED_PLAYER,
		sim.query_player_is_in_build_mode(VIEWED_PLAYER),
		machine,
		tile,
		rotation
	)

	var selected: String = sim.query_player_selected_machine(VIEWED_PLAYER)
	var definition: MachineDefinition = sim.query_definitions().machine(selected)
	# **Hidden rather than reddened, for two reasons that are the same reason.** A red
	# hologram says "not *there*" and invites a player to aim somewhere else, so it is the
	# right answer only when aiming elsewhere would help. Neither of these is that:
	#
	#   the hand   a holstered Build Gun is a fact about what the player is holding, and
	#              nowhere they aim will change it (#35, which found the hologram still
	#              drawn and still green with a rifle in frame);
	#   the tool   with the Belt tool out the route preview is what the button would do, and
	#              two previews of two different acts over one tile is a player guessing
	#              which (#36).
	#
	# A promise nobody can keep is better not made than made in red.
	_hologram.visible = (
		definition != null
		and refusal != Simulation.Refusal.BUILD_GUN_IS_HOLSTERED
		and not sim.query_player_is_laying_belt(VIEWED_PLAYER)
	)
	if not _hologram.visible:
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

	var footprint: Vector2i = WorldGrid.rotated_footprint(declared.x, declared.y, rotation)

	_hologram.rotation = Vector3(0.0, _yaw_for_rotation(rotation), 0.0)
	_hologram.position = _footprint_centre(sim, tile, footprint)
	if not dressing.begins_with("res://"):
		_hologram.position.y += height * 0.5

	var tint: StandardMaterial3D = _hologram.material_override
	tint.albedo_color = (
		HOLOGRAM_ALLOWED
		if refusal == Simulation.Refusal.NONE and where.aim == BuildGun.Aim.ON_TARGET
		else HOLOGRAM_REFUSED
	)


## What the player is told the drag would do: a slab on every tile of the route, the ones
## that would be refused in red, and an arrow a tile pointing the way Items would travel.
##
## **The route is `BeltRoute`'s, the refusal is the Simulation's, and this draws what they
## say.** Nothing here decides anything about a route: a preview with its own opinion about
## where a corner goes or about what is in the way is the defect this whole arrangement
## exists to make impossible — a player would see a green line and get a refusal.
##
## Before the press there is no drag and the preview is the single tile under the aim, which
## is exactly what a click would lay. That is the one case where the route's two ends are the
## same tile, and `BeltRoute` deliberately calls that no route at all — the direction of a
## one-tile Belt is the player's facing and the Simulation owns it, so the preview asks for
## the same thing the intent will.
func _sync_belt_preview(sim: Simulation) -> void:
	var tile_size: float = Fixed.to_float(sim.query_tile_size_metres())
	if _belt_preview == null:
		_belt_preview = _preview_slabs(tile_size, HOLOGRAM_ALLOWED, 0.04)
		_belt_preview_refused = _preview_slabs(
			tile_size, HOLOGRAM_REFUSED, BELT_REFUSED_HEIGHT_METRES
		)
		_belt_preview_arrows = _flow_arrows(tile_size, FLOW_ARROW_COLOUR)

	var laying: bool = sim.query_player_is_laying_belt(VIEWED_PLAYER)
	_belt_preview.visible = laying
	_belt_preview_refused.visible = laying
	_belt_preview_arrows.visible = laying
	if not laying:
		_belt_preview_transforms.resize(0)
		_belt_preview_refused_transforms.resize(0)
		_belt_preview_arrow_transforms.resize(0)
		_belt_preview.multimesh.instance_count = 0
		_belt_preview_refused.multimesh.instance_count = 0
		_belt_preview_arrows.multimesh.instance_count = 0
		return

	var aimed: Vector3i = BuildGun.aimed_tile(sim, VIEWED_PLAYER)
	var from_tile: Vector3i = _belt_drag_anchor if _belt_drag_active else aimed
	var runs: Array = BeltRoute.segments(from_tile, aimed, _belt_drag_corner_axis)

	# **Whether the route lays is a property of the route, so it is the colour of the whole
	# route** — asked of the one function the release goes through, `_belt_route_refusal`,
	# rather than inferred from the tiles. #67, and it is #35's defect in the Belt tool: a
	# route lands whole or not at all, so a ten-tile route with one blocked tile lays
	# *nothing*, and tinting tile by tile painted the other nine in the green a player
	# learns off the Machine hologram as "release it and it goes down".
	#
	# The two marks answer two questions and neither can answer the other's. `MISSING_MATERIALS`
	# is the proof: every tile is clear ground, no tile is markable, and the release is
	# refused — so only the colour of the route can say so. A blocked tile, conversely, is a
	# place rather than a verdict, which is why the standing red volume below stays.
	#
	# **The dock refusals are deliberately not consulted**, exactly as `_belt_route_lines`
	# keeps them out of its verdict: a route whose far end will not hand its goods over lays
	# perfectly well, and a player routes a line in stages past where a Machine is going to
	# stand every day (#56). Advice before the release, never a veto — and never a colour.
	var lays: bool = (
		sim.query_belt_route_refusal(
			VIEWED_PLAYER, from_tile, aimed, _belt_drag_corner_axis
		) == Simulation.Refusal.NONE
	)
	var skin: StandardMaterial3D = _belt_preview.material_override
	skin.albedo_color = HOLOGRAM_ALLOWED if lays else HOLOGRAM_REFUSED

	var clear: PackedFloat32Array = PackedFloat32Array()
	var refused: PackedFloat32Array = PackedFloat32Array()
	var arrows: PackedFloat32Array = PackedFloat32Array()
	if runs.is_empty():
		# The drag that never moved: one tile, aimed along the player's facing, which is the
		# direction the Simulation will give the Belt.
		runs = [
			BeltRoute.Run.new(
				from_tile,
				from_tile,
				WorldGrid.direction_from_turns(sim.query_player_yaw_turns(VIEWED_PLAYER))
			)
		]

	for run: BeltRoute.Run in runs:
		var step: Vector3i = WorldGrid.direction_step(run.direction)
		var yaw: float = _yaw_for_direction(run.direction)
		for offset: int in range(run.length_tiles()):
			var tile: Vector3i = run.from + step * offset
			var centre: FixedVec2 = sim.query_tile_centre_metres(tile)
			var ground: float = Fixed.to_float(sim.query_layer_height_metres(tile.y))
			var at: Vector3 = Vector3(
				Fixed.to_float(centre.x), ground + BELT_PREVIEW_HEIGHT_METRES,
				Fixed.to_float(centre.z)
			)
			var is_clear: bool = (
				sim.query_belt_tile_refusal(tile) == Simulation.Refusal.NONE
			)
			var into: PackedFloat32Array = clear if is_clear else refused
			if not is_clear:
				# The blocked volume, standing over whatever is blocking it.
				at.y = ground + BELT_REFUSED_HEIGHT_METRES * 0.5
			into.resize(into.size() + FLOATS_PER_INSTANCE)
			@warning_ignore("integer_division")
			_write_instance(into, into.size() / FLOATS_PER_INSTANCE - 1, at, yaw)
			if not is_clear:
				# No flow arrow on a tile nothing will flow along, and nowhere to put one
				# that would not be inside the obstruction.
				continue
			arrows.resize(arrows.size() + FLOATS_PER_INSTANCE)
			@warning_ignore("integer_division")
			_write_instance(
				arrows,
				arrows.size() / FLOATS_PER_INSTANCE - 1,
				Vector3(at.x, ground + FLOW_ARROW_LIFT_METRES, at.z),
				yaw
			)

	_belt_preview_transforms = clear
	_belt_preview_refused_transforms = refused
	_belt_preview_arrow_transforms = arrows
	_upload(_belt_preview, clear)
	_upload(_belt_preview_refused, refused)
	_upload(_belt_preview_arrows, arrows)


## An arrow on every port of every Machine standing, and of the one about to land.
##
## **Read out of `content/machine_ports.csv` through `Definitions`**, which is the file the
## Blender generator put the mesh markers from — so the arrow and the moulded port on the
## model are one declaration and not two. The rotation is the Machine's own, through
## `MachinePorts.port_tile`, which shares `WorldGrid.rotated_footprint`'s convention: that is
## what keeps the arrows on the body of a 3x2 Boiler turned a quarter.
##
## The hologram's ports are in the same buffers as the standing Machines', because they are
## the same question asked a second earlier: which way round will this thing's faces be. They
## go away with the hologram, so the Belt tool shows a route and nothing else.
func _sync_ports(sim: Simulation) -> void:
	var tile_size: float = Fixed.to_float(sim.query_tile_size_metres())
	if _input_ports == null:
		# Bigger than the Belt's own flow arrows: a port arrow is a thing a player goes
		# looking for while deciding where to build, and the small one a render showed was
		# invisible at the distance anybody actually works from.
		_input_ports = _flow_arrows(tile_size * PORT_MARKER_SCALE, PORT_INPUT_COLOUR)
		_output_ports = _flow_arrows(tile_size * PORT_MARKER_SCALE, PORT_OUTPUT_COLOUR)

	var definitions: Definitions = sim.query_definitions()
	var ports: MachinePorts = definitions.machine_ports()
	var into: PackedFloat32Array = PackedFloat32Array()
	var out_of: PackedFloat32Array = PackedFloat32Array()

	if not _ports_are_advice_right_now(sim):
		_input_port_transforms = into
		_output_port_transforms = out_of
		_upload(_input_ports, into)
		_upload(_output_ports, out_of)
		return

	var asked_about: Array[Vector3i] = _where_the_ports_are_being_asked_about(sim)
	for index: int in range(sim.query_machine_count()):
		var id: String = sim.query_machine_id(index)
		var definition: MachineDefinition = definitions.machine(id)
		if definition == null:
			continue
		var declared: Array[MachinePorts.Port] = ports.ports_of(id)
		var origin: Vector3i = sim.query_machine_tile(index)
		var rotated: int = sim.query_machine_rotation(index)
		# **Whole Machine or none of it, which a render decided.** Filtered dock tile by dock
		# tile, a Machine straddling the range showed the arrows on its near face and not the
		# ones on its far one — and a face that is half drawn reads as the whole declaration,
		# which is a worse thing to tell a player than nothing. So the range decides which
		# Machine is being asked about and the answer is always its whole declaration.
		if not _machine_is_being_asked_about(
			declared, definition, origin, rotated, asked_about
		):
			continue
		_mark_ports(sim, declared, definition, origin, rotated, into, out_of)

	# The Machine about to land, on the tile it would land on, turned the way it would be
	# turned. Only while the hologram is up: with the Belt tool out the route is what the
	# button would do, and two sets of arrows over one tile is a player guessing.
	if hologram_is_visible():
		var selected: String = sim.query_player_selected_machine(VIEWED_PLAYER)
		var about_to_land: MachineDefinition = definitions.machine(selected)
		if about_to_land != null:
			# The tile the hologram is standing on, not the one under the crosshair. Since
			# #42 a Miner's are different, and ports drawn at the aim while the body sits
			# on the Node would be arrows pointing at nothing.
			var rotation: int = sim.query_player_build_rotation(VIEWED_PLAYER)
			var where: BuildGun.Placement = BuildGun.placement(
				sim,
				VIEWED_PLAYER,
				sim.query_player_selected_machine_index(VIEWED_PLAYER),
				rotation
			)
			# No filter: the Machine about to land *is* what the gun is pointing at, so
			# every face of it is the question being asked.
			_mark_ports(
				sim, ports.ports_of(selected), about_to_land, where.tile, rotation, into, out_of
			)

	_input_port_transforms = into
	_output_port_transforms = out_of
	_upload(_input_ports, into)
	_upload(_output_ports, out_of)


## Whether a port arrow is advice this player could act on, which is the whole of #66's
## first fault.
##
## **`BuildGun.hand_refusal` is the one home for "is this player in a position to build"**,
## and the port arrows had never asked it. Since #42 the weapon is the default hand, so the
## state a player spends most of a Run in was the state in which every tile of every face of
## every Machine wore a 3.2 m warm-orange quad at deck height — measured off the shipped
## table, eight of the ten Machines declare every tile of every face, so a square Smelter
## wears twelve and the Factory wears a hedge. An arrow is advice about where to put a Belt
## and a player holding a rifle is not putting one anywhere.
##
## Deliberately the **hand** and not the tool: the Machine tool is how a player decides which
## way round to turn the thing they are about to place, which is a question entirely about
## ports, and the Belt tool is how they act on the answer.
func _ports_are_advice_right_now(sim: Simulation) -> bool:
	return BuildGun.hand_refusal(
		sim.query_player_is_in_build_mode(VIEWED_PLAYER)
	) == Simulation.Refusal.NONE


## The tiles the Build Gun is asking a question about this frame, which is what the port
## arrows are drawn around.
##
## Where it is pointing, always — and with a Belt drag in flight, the tile the drag was
## anchored on as well, because a route has two ends and the far one is the one a player
## committed to several seconds ago. Without it the arrow that started the drag goes out
## while the drag is being made, which is the one moment it is being read.
func _where_the_ports_are_being_asked_about(sim: Simulation) -> Array[Vector3i]:
	var asked: Array[Vector3i] = [BuildGun.aimed_tile(sim, VIEWED_PLAYER)]
	if _belt_drag_active:
		asked.append(_belt_drag_anchor)
	return asked


## Whether any of a Machine's dock tiles is within `PORT_ARROW_RANGE_TILES` of something the
## Build Gun is asking about. Its *dock* tiles rather than its footprint, because the dock
## tile is where the arrow stands and where the Belt goes — so the thing the range is about
## and the thing it measures are one.
##
## Compared squared, the way every reach in this project is, so there is no rounding rule
## deciding whether a tile exactly on the boundary is in or out. The hologram's own ports do
## not come through here at all: the Machine about to land *is* what the gun is pointing at.
static func _machine_is_being_asked_about(
	ports: Array[MachinePorts.Port],
	definition: MachineDefinition,
	origin: Vector3i,
	rotation: int,
	asked_about: Array[Vector3i]
) -> bool:
	for port: MachinePorts.Port in ports:
		var tile: Vector3i = MachinePorts.dock_tile(
			port, origin, definition.footprint_x, definition.footprint_z, rotation
		)
		for about: Vector3i in asked_about:
			var gap_x: int = tile.x - about.x
			var gap_z: int = tile.z - about.z
			if gap_x * gap_x + gap_z * gap_z <= PORT_ARROW_RANGE_TILES * PORT_ARROW_RANGE_TILES:
				return true
	return false


## Writes one Machine's declared ports into the two buffers.
##
## The arrow points **the way goods travel**: along the port's outward direction for an
## output, against it for an input. That is the thing a player is trying to work out, and it
## is one subtraction from the same number rather than a second declaration.
func _mark_ports(
	sim: Simulation,
	ports: Array[MachinePorts.Port],
	definition: MachineDefinition,
	origin: Vector3i,
	rotation: int,
	into: PackedFloat32Array,
	out_of: PackedFloat32Array
) -> void:
	for port: MachinePorts.Port in ports:
		# **The dock tile, not the port tile.** The port itself is a tile of the Machine's own
		# footprint, and a marker there is a marker *inside* the body — invisible, which a
		# render showed immediately. The tile just outside it is both visible and the more
		# useful answer: it is where the Belt goes.
		var tile: Vector3i = MachinePorts.dock_tile(
			port, origin, definition.footprint_x, definition.footprint_z, rotation
		)
		var facing: int = MachinePorts.port_direction(port, rotation)
		var travel: int = (
			WorldGrid.wrap_rotation(facing + 2) if port.is_an_input() else facing
		)
		var centre: FixedVec2 = sim.query_tile_centre_metres(tile)
		var at: Vector3 = Vector3(
			Fixed.to_float(centre.x),
			Fixed.to_float(sim.query_layer_height_metres(tile.y)) + PORT_MARKER_HEIGHT_METRES,
			Fixed.to_float(centre.z)
		)
		var buffer: PackedFloat32Array = into if port.is_an_input() else out_of
		buffer.resize(buffer.size() + FLOATS_PER_INSTANCE)
		@warning_ignore("integer_division")
		_write_instance(
			buffer, buffer.size() / FLOATS_PER_INSTANCE - 1, at, _yaw_for_direction(travel)
		)


## How many port markers are on screen. For the smoke test.
func port_marker_count() -> int:
	return input_port_marker_count() + output_port_marker_count()


## How many of them are inputs. For the smoke test.
func input_port_marker_count() -> int:
	@warning_ignore("integer_division")
	return _input_port_transforms.size() / FLOATS_PER_INSTANCE


## How many of them are outputs. For the smoke test.
func output_port_marker_count() -> int:
	@warning_ignore("integer_division")
	return _output_port_transforms.size() / FLOATS_PER_INSTANCE


## Where an output port's marker was drawn, in metres. For the smoke test.
func output_port_marker_position(marker: int) -> Vector3:
	return _instance_position(_output_port_transforms, marker)


## Where an input port's marker was drawn, in metres. For the smoke test.
func input_port_marker_position(marker: int) -> Vector3:
	return _instance_position(_input_port_transforms, marker)


## What is wrong with the Factory, marked where it is wrong: a post at every Belt end that
## leads nowhere, a tag over every starved Machine, and an arrow a tile saying which way each
## Belt carries.
##
## **Every one of the three is a query**. `query_belt_start_is_fed` and
## `query_belt_end_is_connected` ask the geometry half of the hand-off the Simulation itself
## performs, and `query_machine_is_starved` answers for a Miner over the wrong ground and a
## crafter with half a Recipe alike — so a renderer that inferred any of it from a count that
## had stopped moving would be a second opinion, and the wrong one on the frame they
## disagreed.
func _sync_connection_marks(sim: Simulation) -> void:
	var tile_size: float = Fixed.to_float(sim.query_tile_size_metres())
	if _dangling_marks == null:
		_dangling_marks = _marker_posts(tile_size, DANGLING_COLOUR)
		_starved_marks = _marker_posts(tile_size, STARVED_COLOUR)
		_starved_tethers = _unshaded_tags(
			Vector3(
				tile_size * STARVED_TETHER_THICKNESS_TILES,
				STARVED_MARK_LIFT_METRES,
				tile_size * STARVED_TETHER_THICKNESS_TILES
			),
			STARVED_COLOUR
		)
		_belt_flow_arrows = _flow_arrows(tile_size, FLOW_ARROW_COLOUR)

	var dangling: PackedFloat32Array = PackedFloat32Array()
	var flow: PackedFloat32Array = PackedFloat32Array()
	for index: int in range(sim.query_belt_count()):
		var direction: int = sim.query_belt_direction(index)
		var yaw: float = _yaw_for_direction(direction)
		var length: int = sim.query_belt_length_tiles(index)
		# The height is the one decision here and it is per end: a post at a Machine's wall is
		# standing on a dock tile among 3.2 m port arrows and has to clear them, where one on
		# open ground has nothing to clear and belongs at hip height. Which it is comes off
		# the dock refusal — the same projection the HUD's sentence does — so the mark that
		# says *where* and the line that says *what to do* cannot end up about different ends.
		if not sim.query_belt_start_is_fed(index):
			_mark_at(
				sim,
				dangling,
				sim.query_belt_tile(index, 0),
				_dangling_mark_height(sim.query_belt_start_dock_refusal(index)),
				yaw
			)
		if not sim.query_belt_end_is_connected(index):
			_mark_at(
				sim,
				dangling,
				sim.query_belt_tile(index, length - 1),
				_dangling_mark_height(sim.query_belt_end_dock_refusal(index)),
				yaw
			)
		for tile: int in range(length):
			_mark_at(
				sim, flow, sim.query_belt_tile(index, tile),
				Fixed.to_float(sim.query_belt_deck_height_metres()) + FLOW_ARROW_LIFT_METRES,
				yaw
			)

	var starved: PackedFloat32Array = PackedFloat32Array()
	var tethers: PackedFloat32Array = PackedFloat32Array()
	for index: int in range(sim.query_machine_count()):
		if not sim.query_machine_is_starved(index):
			continue
		var centre: Vector3 = _machine_centre(sim, index)
		var roof: float = _machine_roof(sim, index)
		starved.resize(starved.size() + FLOATS_PER_INSTANCE)
		@warning_ignore("integer_division")
		_write_instance(
			starved,
			starved.size() / FLOATS_PER_INSTANCE - 1,
			Vector3(centre.x, centre.y + roof + STARVED_MARK_LIFT_METRES, centre.z),
			0.0
		)
		# And the line that says whose tag it is, filling the gap the lift leaves — from the
		# top of the body a player can see up to the tag resting over it.
		tethers.resize(tethers.size() + FLOATS_PER_INSTANCE)
		@warning_ignore("integer_division")
		_write_instance(
			tethers,
			tethers.size() / FLOATS_PER_INSTANCE - 1,
			Vector3(centre.x, centre.y + roof + STARVED_MARK_LIFT_METRES * 0.5, centre.z),
			0.0
		)

	_dangling_transforms = dangling
	_starved_transforms = starved
	_starved_tether_transforms = tethers
	_belt_flow_transforms = flow
	_upload(_dangling_marks, dangling)
	_upload(_starved_marks, starved)
	_upload(_starved_tethers, tethers)
	_upload(_belt_flow_arrows, flow)


## What a split is doing, marked where it is happening: a tag over every Machine serving two
## or more Belts, and a post at each of those Belts' entry tiles saying whether it is taking
## its turn.
##
## **The three things #48 draws, in the order the ticket ranks them.** That the Machine splits
## at all, so a player knows they built one rather than two Belts that happen to touch. Which
## branch is blocked, which is the one a player has to act on and the one a Factory seen from
## above cannot say. And that the surplus is banking rather than being lost, which
## `query_machine_output_total` knows and nothing had ever shown.
##
## **Blocked is `query_belt_is_stalled` and not "no room at the entry".** A healthy saturated
## branch has no room at its entry on most ticks — the room check is what rate-limits loading
## to the Belt's rating — so marking that would flicker on a line that is working perfectly.
## Stalled is the stable fact: the leading Item has reached the far end and whatever is there
## will not take it.
##
## **And only inside a branch**, deliberately. The confusion this is drawn for is *between*
## two Belts off one Machine; a single line that is backed up is already legible as a Belt
## packed solid, and it is named in the HUD. A post on every stalled Belt in a late Factory
## would be a post on most of them.
func _sync_split_marks(sim: Simulation) -> void:
	var tile_size: float = Fixed.to_float(sim.query_tile_size_metres())
	if _split_marks == null:
		_split_marks = _split_tags(SPLIT_COLOUR)
		_banking_marks = _split_tags(BANKING_COLOUR)
		_branch_marks = _branch_posts(SPLIT_COLOUR)
		_blocked_branch_marks = _branch_posts(BLOCKED_BRANCH_COLOUR)

	var split: PackedFloat32Array = PackedFloat32Array()
	var banking: PackedFloat32Array = PackedFloat32Array()
	var branch: PackedFloat32Array = PackedFloat32Array()
	var blocked: PackedFloat32Array = PackedFloat32Array()

	for index: int in range(sim.query_machine_count()):
		var branches: int = sim.query_machine_branch_count(index)
		if branches < 2:
			continue

		var stopped: int = 0
		for which: int in range(branches):
			var belt: int = sim.query_machine_branch_belt(index, which)
			var entry: Vector3i = sim.query_belt_tile(belt, 0)
			var yaw: float = _yaw_for_direction(sim.query_belt_direction(belt))
			# A branch that leads nowhere already wears a red dangling post at this very
			# tile, so marking it blocked as well would stack two reds on one tile for one
			# mistake. Blocked means it leads somewhere and cannot get there.
			if sim.query_belt_is_stalled(belt) and sim.query_belt_end_is_connected(belt):
				_mark_at(sim, blocked, entry, BRANCH_MARK_HEIGHT_METRES, yaw)
				stopped += 1
				continue
			_mark_at(sim, branch, entry, BRANCH_MARK_HEIGHT_METRES, yaw)
			if sim.query_belt_is_stalled(belt):
				stopped += 1

		# Both branches stopped and the Machine still holding goods is the one case where a
		# player needs telling that nothing is being destroyed.
		var is_banking: bool = stopped == branches and sim.query_machine_output_total(index) > 0
		_write_mark_over_machine(sim, banking if is_banking else split, index)

	_split_transforms = split
	_banking_transforms = banking
	_branch_transforms = branch
	_blocked_branch_transforms = blocked
	_upload(_split_marks, split)
	_upload(_banking_marks, banking)
	_upload(_branch_marks, branch)
	_upload(_blocked_branch_marks, blocked)


## Writes one tag over a Machine's own roof, at `SPLIT_MARK_LIFT_METRES`.
##
## The position comes from `_machine_centre`, which is what `_sync_machines` seats the body
## with and what `_turret_gauge_position` hangs the Ammunition bar from, so a tag cannot end
## up over a different Machine from the one it is about. The height is `_machine_roof`.
func _write_mark_over_machine(
	sim: Simulation, into: PackedFloat32Array, index: int
) -> void:
	var centre: Vector3 = _machine_centre(sim, index)
	var lift: float = maxf(
		_machine_roof(sim, index) + SPLIT_MARK_CLEARS_THE_BODY_METRES,
		Fixed.to_float(sim.query_machine_height_metres(index))
			+ SPLIT_MARK_CLEARS_THE_ROOF_METRES
	)
	into.resize(into.size() + FLOATS_PER_INSTANCE)
	@warning_ignore("integer_division")
	_write_instance(
		into,
		into.size() / FLOATS_PER_INSTANCE - 1,
		Vector3(centre.x, centre.y + lift, centre.z),
		0.0
	)


## The top of what a player can actually see of a Machine: the taller of the housing the
## Simulation collides against and the body the renderer is drawing.
##
## **This is #41's rule kept rather than bent, and a render is what found the difference.**
## `query_machine_height_metres` is the one authority on how tall a Machine *is* — the number
## a player stands on, the number a placeholder box is sized from — and a mark hung off a
## constant instead is what shipped #41's ownerless red rectangle. But it is the **housing**
## height, and several generated bodies carry a superstructure well above theirs: a Smelter's
## housing is 1.5 m and its flue goes to about five, a Miner's is 1.8 m under a derrick. A tag
## 2.1 m over a Smelter's housing is a tag *inside the chimney*, which is the same bug as #41
## pointed the other way — and the count, the colour and the position were all correct, so
## nothing but looking at the picture would have found it.
##
## So the roof is the **max** of the two. The Simulation's figure is a floor and never
## contradicted, the mesh is asked only about its own extent, and neither is a constant.
##
## **Every mark a Machine wears is measured from here**: the amber starved tag, the
## Ammunition gauge and the three split tags. #48 built this and used it for its own three,
## recording that the other two had the same defect and belonged to their own ticket; #50 is
## that ticket, and pointing them here is the whole of it.
func _machine_roof(sim: Simulation, index: int) -> float:
	var housing: float = Fixed.to_float(sim.query_machine_height_metres(index))
	if index < 0 or index >= _machine_meshes.size():
		return housing
	var mesh: Mesh = _machine_meshes[index].mesh
	if mesh == null:
		return housing
	# A body is modelled about the centre of its footprint with its feet on the ground, so its
	# own AABB already runs from zero to its full height. A placeholder box is modelled about
	# its centre and lifted, which is why that case falls back to the declared figure.
	if not machine_body_path(index).begins_with("res://"):
		return housing
	return maxf(housing, mesh.get_aabb().end.y)


## How high the top of the body drawn for a Machine is, in metres. For the smoke test, which
## asserts the split tag clears it rather than asserting a number.
func machine_drawn_roof_metres(sim: Simulation, index: int) -> float:
	return _machine_roof(sim, index)


## A MultiMesh of branch posts: a short pillar standing clear of the Belt deck at the entry
## tile it is about. Taller than it is wide, so that a row of them along a line of Belts reads
## as a row of markers rather than as more freight.
func _branch_posts(colour: Color) -> MultiMeshInstance3D:
	return _unshaded_tags(
		Vector3(
			BRANCH_MARK_SIZE_METRES * 0.42,
			BRANCH_MARK_SIZE_METRES,
			BRANCH_MARK_SIZE_METRES * 0.42
		),
		colour
	)


## A MultiMesh of split tags: a flat slab over a Machine's roof, wide rather than tall, which
## is the shape that reads from above and from the side alike.
func _split_tags(colour: Color) -> MultiMeshInstance3D:
	return _unshaded_tags(
		Vector3(
			SPLIT_MARK_SIZE_METRES, SPLIT_MARK_SIZE_METRES * 0.3, SPLIT_MARK_SIZE_METRES
		),
		colour
	)


## One MultiMesh of boxes in one colour. Unshaded for the reason every diagnostic in this file
## is: a mark a directional light can darken is a mark a player misreads at the worst moment.
func _unshaded_tags(size: Vector3, colour: Color) -> MultiMeshInstance3D:
	var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
	var instanced: MultiMesh = MultiMesh.new()
	instanced.transform_format = MultiMesh.TRANSFORM_3D
	var tag: BoxMesh = BoxMesh.new()
	tag.size = size
	instanced.mesh = tag
	node.multimesh = instanced
	var skin: StandardMaterial3D = StandardMaterial3D.new()
	skin.albedo_color = colour
	skin.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	skin.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	node.material_override = skin
	add_child(node)
	return node


## How many Machines are marked as serving a flowing split. For the smoke test, and the number
## the HUD reports.
func split_marker_count() -> int:
	@warning_ignore("integer_division")
	return _split_transforms.size() / FLOATS_PER_INSTANCE


## How many splits are marked as banking their surplus, both branches stopped.
func banking_marker_count() -> int:
	@warning_ignore("integer_division")
	return _banking_transforms.size() / FLOATS_PER_INSTANCE


## How many branch posts stand at Belts that are taking their turn.
func branch_marker_count() -> int:
	@warning_ignore("integer_division")
	return _branch_transforms.size() / FLOATS_PER_INSTANCE


## How many branch posts stand at Belts that are blocked.
func blocked_branch_marker_count() -> int:
	@warning_ignore("integer_division")
	return _blocked_branch_transforms.size() / FLOATS_PER_INSTANCE


## Where a split's tag is drawn, so a test can check it hangs off its own Machine's roof
## rather than off a constant. `Vector3.ZERO` for an index nothing was marked at.
func split_marker_position(which: int) -> Vector3:
	return _instance_position(_split_transforms, which)


## Where a branch post is drawn, in the canonical order the Simulation serves the branch in.
func branch_marker_position(which: int) -> Vector3:
	return _instance_position(_branch_transforms, which)


## Writes one mark over the centre of a tile.
func _mark_at(
	sim: Simulation, into: PackedFloat32Array, tile: Vector3i, lift: float, yaw: float
) -> void:
	var centre: FixedVec2 = sim.query_tile_centre_metres(tile)
	into.resize(into.size() + FLOATS_PER_INSTANCE)
	@warning_ignore("integer_division")
	_write_instance(
		into,
		into.size() / FLOATS_PER_INSTANCE - 1,
		Vector3(
			Fixed.to_float(centre.x),
			Fixed.to_float(sim.query_layer_height_metres(tile.y)) + lift,
			Fixed.to_float(centre.z)
		),
		yaw
	)


## A MultiMesh of small unshaded tags, one per thing being complained about. Unshaded on
## purpose: a diagnostic has to read the same on the dark side of a Boiler as on the lit one.
func _marker_posts(tile_size: float, colour: Color) -> MultiMeshInstance3D:
	var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
	var instanced: MultiMesh = MultiMesh.new()
	instanced.transform_format = MultiMesh.TRANSFORM_3D
	var tag: BoxMesh = BoxMesh.new()
	tag.size = Vector3(tile_size * 0.22, tile_size * 0.22, tile_size * 0.22)
	instanced.mesh = tag
	node.multimesh = instanced
	var skin: StandardMaterial3D = StandardMaterial3D.new()
	skin.albedo_color = colour
	skin.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	skin.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	node.material_override = skin
	add_child(node)
	return node


## How many Belt ends are marked as leading nowhere. For the smoke test, and the number the
## HUD reports.
func dangling_marker_count() -> int:
	@warning_ignore("integer_division")
	return _dangling_transforms.size() / FLOATS_PER_INSTANCE


## How high a dangling post stands, given why its end was refused: clear of the port arrows
## when a Machine's wall is what refused it, hip height when nothing is there.
func _dangling_mark_height(dock_refusal: int) -> float:
	if dock_refusal == Simulation.Refusal.NONE:
		return DANGLING_MARK_HEIGHT_METRES
	return DANGLING_AT_A_WALL_HEIGHT_METRES


## Where a dangling post was drawn, in metres. For the smoke test and for
## `tools/visual/compose_dock_shot.gd`, which has to be able to say whether a post that is not
## in the picture was hidden behind something or was never drawn — #48's third render spent
## three attempts on exactly that question.
func dangling_marker_position(marker: int) -> Vector3:
	return _instance_position(_dangling_transforms, marker)


## How many Machines are marked as starved. For the smoke test.
func starved_marker_count() -> int:
	@warning_ignore("integer_division")
	return _starved_transforms.size() / FLOATS_PER_INSTANCE


## Where a starved tag is drawn, in Machine index order. For the smoke test, which asserts it
## clears the body a player can see rather than asserting a number.
func starved_marker_position(which: int) -> Vector3:
	return _instance_position(_starved_transforms, which)


## How many starved tags are tethered to the body under them. One per tag, always — a tag
## without one is #41's ownerless mark, which is what this count exists to refuse.
func starved_tether_count() -> int:
	@warning_ignore("integer_division")
	return _starved_tether_transforms.size() / FLOATS_PER_INSTANCE


## Where a tether's middle is, in metres. For the smoke test, which asserts it spans the gap
## between the drawn roof and the tag rather than asserting a number.
func starved_tether_position(which: int) -> Vector3:
	return _instance_position(_starved_tether_transforms, which)


## How many flow arrows are drawn along the Belts that are standing. For the smoke test.
func belt_flow_arrow_count() -> int:
	@warning_ignore("integer_division")
	return _belt_flow_transforms.size() / FLOATS_PER_INSTANCE


## Hands a MultiMesh its instances, or tells it there are none. The buffer may only be
## assigned when there is at least one instance to put in it.
func _upload(into: MultiMeshInstance3D, transforms: PackedFloat32Array) -> void:
	@warning_ignore("integer_division")
	var count: int = transforms.size() / FLOATS_PER_INSTANCE
	into.multimesh.instance_count = count
	if count > 0:
		into.multimesh.buffer = transforms


## A MultiMesh of flat translucent slabs, one a tile. The shape of a tile of Belt before
## there is a tile of Belt.
func _preview_slabs(tile_size: float, colour: Color, height: float) -> MultiMeshInstance3D:
	var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
	var instanced: MultiMesh = MultiMesh.new()
	instanced.transform_format = MultiMesh.TRANSFORM_3D
	var slab: BoxMesh = BoxMesh.new()
	slab.size = Vector3(tile_size * 0.82, height, tile_size * 0.82)
	instanced.mesh = slab
	node.multimesh = instanced
	var skin: StandardMaterial3D = StandardMaterial3D.new()
	skin.albedo_color = colour
	skin.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	skin.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	node.material_override = skin
	add_child(node)
	return node


## A MultiMesh of flat chevrons, each pointing along its own **local +z** — which is where
## `_write_instance` puts a yaw's forward, so one yaw out of `_yaw_for_direction` aims it
## down the flow.
##
## Built by hand rather than out of a primitive because every primitive that is a wedge
## points along an axis this does not want, and baking the correction into the vertices is
## cheaper than a second transform per instance on a mesh drawn hundreds of times.
func _flow_arrows(tile_size: float, colour: Color) -> MultiMeshInstance3D:
	var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
	var instanced: MultiMesh = MultiMesh.new()
	instanced.transform_format = MultiMesh.TRANSFORM_3D
	instanced.mesh = _chevron_mesh(tile_size * 0.3)
	node.multimesh = instanced
	var skin: StandardMaterial3D = StandardMaterial3D.new()
	skin.albedo_color = colour
	skin.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	skin.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	node.material_override = skin
	add_child(node)
	return node


## One flat arrowhead in the xz plane, apex at +z, drawn both ways round so it reads from
## above and from underneath a Belt deck.
func _chevron_mesh(reach: float) -> Mesh:
	var vertices: PackedVector3Array = PackedVector3Array([
		Vector3(0.0, 0.0, reach),
		Vector3(-reach * 0.8, 0.0, -reach * 0.6),
		Vector3(reach * 0.8, 0.0, -reach * 0.6),
		Vector3(0.0, 0.0, reach),
		Vector3(reach * 0.8, 0.0, -reach * 0.6),
		Vector3(-reach * 0.8, 0.0, -reach * 0.6),
	])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## How many tiles of route are being previewed. For the smoke test, and the number the HUD
## reports as a length.
func belt_preview_tile_count() -> int:
	@warning_ignore("integer_division")
	return (
		_belt_preview_transforms.size() + _belt_preview_refused_transforms.size()
	) / FLOATS_PER_INSTANCE


## How many of them are marked as refused. For the smoke test.
func belt_preview_refused_tile_count() -> int:
	@warning_ignore("integer_division")
	return _belt_preview_refused_transforms.size() / FLOATS_PER_INSTANCE


## Whether the route in flight is drawn in the colour that means "release it and it goes
## down" — `HOLOGRAM_ALLOWED`, the green a player learns off the Machine hologram.
##
## Read off the material the slabs are actually painted with rather than off a flag, because
## a flag is a second opinion about what is on screen and the thing under test here is the
## picture.
func belt_preview_promises_a_lay() -> bool:
	if _belt_preview == null:
		return false
	var skin: StandardMaterial3D = _belt_preview.material_override
	return skin != null and skin.albedo_color == HOLOGRAM_ALLOWED


## Where the drag the renderer is drawing started, and which way its corner bends. Handed
## over by `Main` once a frame, straight off the controller.
func note_belt_drag(active: bool, anchor: Vector3i, corner_axis: int) -> void:
	_belt_drag_active = active
	_belt_drag_anchor = anchor
	_belt_drag_corner_axis = corner_axis


## Whether the Build Gun's promise is in frame at all. For the tests, and for `_sync_ports`,
## which hangs the about-to-land Machine's port arrows off the same answer.
##
## False in three cases, and none of them is a refusal a player could aim their way out of:
## with the Build Gun holstered (#35), with the Belt tool out, because the route preview is
## what the button would do and two previews over one tile is a player guessing (#36), and
## while the Build Gun is holding a Machine the definition set does not have.
func hologram_is_visible() -> bool:
	return _hologram != null and _hologram.visible


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
