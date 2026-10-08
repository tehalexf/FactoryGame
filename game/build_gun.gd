## Where the Build Gun is pointing, and what to tell a player when it refuses.
##
## The tool through which all construction happens, available at all times including
## mid-Wave (GLOSSARY.md). There is no mode to enter: nothing here asks whether building
## is allowed, because nothing in the Simulation would answer.
##
## It holds no state. The aim is a function of what the Simulation says about the camera,
## so the controller and the renderer can both ask and cannot disagree — the controller
## to put a tile in a build intent, the renderer to draw the hologram on the same tile.
##
## Floats appear here freely. This is the Godot side, and the aim crosses back into the
## Simulation as a whole tile, through `InputQuantiser`.
class_name BuildGun
extends RefCounted

## How far the Build Gun will place from the player, in metres. Eight tiles: far enough
## to lay out a line without walking every step of it, near enough that a player is
## working on the Factory in front of them rather than one on the horizon.
##
## An aiming limit rather than a rule of the Simulation, and that is deliberate — see
## `InputQuantiser.aimed_tile`. It is a constant rather than a tuning value for the same
## reason: a tuning key the Simulation does not read is a key `Definitions` warns about,
## and until reach is authoritative the Simulation has no business reading it.
const REACH_METRES: float = 16.0


## The tile a player's Build Gun is aimed at.
##
## Derived entirely from queries: where the Simulation says the camera is, and which way
## it says the camera is pointing. Nothing is remembered between frames, so there is no
## second opinion about the aim to drift from the first.
##
## The *camera* pitch rather than the player's own, so aiming works in Survey View — which
## is the whole point of Survey View, since a Factory is illegible at eye level.
static func aimed_tile(sim: Simulation, player_id: int) -> Vector3i:
	var ground: FixedVec2 = sim.query_player_camera_ground_metres(player_id)
	var camera: Vector3 = Vector3(
		Fixed.to_float(ground.x),
		Fixed.to_float(sim.query_player_camera_height_metres(player_id)),
		Fixed.to_float(ground.z)
	)
	var forward: Vector3 = InputQuantiser.forward_vector(
		sim.query_player_yaw_turns(player_id), sim.query_player_camera_pitch_turns(player_id)
	)
	return InputQuantiser.aimed_tile(
		camera, forward, REACH_METRES, Fixed.to_float(sim.query_tile_size_metres())
	)


## How far from the aimed tile the Build Gun will look for a Node to put a Miner on, in
## tiles. Five: a little over the 2x2 Miner itself, so a player aiming anywhere on or
## beside the ore gets it, and short enough that two Nodes eight tiles apart are still two
## places rather than one magnet.
##
## A constant here rather than a key in `content/tuning.toml`, for the reason
## `REACH_METRES` is one: the Simulation does not read it and a tuning key the Simulation
## does not read is a key `Definitions` warns about. It is a property of the aim, and the
## aim lives on this side of the boundary.
const MINER_SNAP_RANGE_TILES: int = 5


## What the Build Gun would do with the tile it is pointing at, and why it would not.
##
## `aim` is this file's own enum rather than a `Simulation.Refusal`, deliberately: a
## `Refusal` is the Simulation's answer about a placement, and these two are facts about
## *aiming* that the Simulation has never had an opinion on — the same standing
## `REACH_METRES` has. The renderer asks this first and `query_build_refusal` second, so a
## player over a Node with no plate reads "not enough materials" and a player over bare
## rock reads "no ore in range".
enum Aim {
	## There is somewhere to put it. The tile is either the aim, or the snap.
	ON_TARGET = 0,
	## A Miner, with no Node it could work inside `MINER_SNAP_RANGE_TILES`.
	NO_NODE_IN_RANGE = 1,
	## A Miner, with a Node in range whose Depth its `max_depth` does not reach. A
	## different reason from the one above because the answer is different: the way past
	## a seam you cannot lift is the next Miner up, not aiming somewhere else.
	NODE_TOO_DEEP = 2,
}


## Where a Machine would land: the tile, whether the aim was moved to get there, and the
## reason it would be refused before the Simulation is even asked.
class Placement:
	extends RefCounted
	var tile: Vector3i = Vector3i.ZERO
	var snapped: bool = false
	var aim: int = Aim.ON_TARGET


## Where a Miner aimed at `aimed` would actually be built, or why it would not be.
##
## ── Why this is in `game/` and not in the Simulation ─────────────────────────
##
## The snap changes **which tile is built on**, so it cannot be a thing the renderer does
## and the apply does not know about. There were two ways to make the hologram and the
## placement one answer, and this is the argument for the one taken.
##
## The other way was for the Simulation to snap: `_apply_build_machine` moves the tile in
## the intent before placing. It replays — the arithmetic is integer and exact — but it
## makes the Simulation **silently relocate an intent**, which is the one thing this
## codebase has consistently refused to do. `WRONG_SLOT` exists because a component fitted
## to the wrong slot is "refused rather than redirected: the intent is meant to describe
## the fitting completely, and silently moving it somewhere else would make a recorded
## script lie about what happened" (CLAUDE.md). `SET_BUILD_MODE` carries the resulting
## mode rather than a flip so "a recorded script describes what the player ended up
## holding without being replayed to find out". A `BUILD_MACHINE` whose tile the
## Simulation moves breaks both of those sentences at once: you could no longer read a
## replay and know where the Factory went, and every Miner in every fixture and every
## recorded session ever made would quietly move to the nearest Node.
##
## So the snap is **aiming**, and aiming already lives here. `REACH_METRES` is the
## precedent and it is an exact one: a player pointing at the horizon does not get an
## `OUT_OF_REACH` refusal, they get a build sixteen metres away, because `aimed_tile`
## decided where the gun was pointing before anything crossed the boundary. This decides
## the same thing with one more fact in hand. What crosses is a tile, as it always was,
## and a replay is therefore byte-identical by construction rather than by the snap being
## careful.
##
## The hologram and the placement agree because **both call this**, which is the same
## arrangement `query_build_refusal` has and the same one `aimed_tile` already had.
##
## ── The rule ─────────────────────────────────────────────────────────────────
##
## Only a Miner snaps. The nearest Node it could really work — its Recipe produces that
## Resource *and* its `max_depth` reaches that Depth, both asked of the Simulation so the
## rule is not copied — inside `MINER_SNAP_RANGE_TILES`, measured as a square ring from
## the aimed tile. The footprint is centred on the Node rather than anchored at it, so a
## bigger Miner covers it from the middle and a quarter turn does not slide it off.
##
## Ties go to the lowest Node index, which is `MapLayout`'s canonical order and therefore
## a property of the Map rather than of anything that happened.
static func snap_to_a_node(
	sim: Simulation, machine_index: int, rotation: int, aimed: Vector3i
) -> Placement:
	var placement: Placement = Placement.new()
	placement.tile = aimed

	var definition: MachineDefinition = sim.query_definitions().machine_at(machine_index)
	if definition == null or not definition.is_miner():
		return placement

	var nearest: int = -1
	var nearest_distance: int = MINER_SNAP_RANGE_TILES + 1
	var too_deep: bool = false
	for index: int in range(sim.query_node_count()):
		var node: Vector3i = sim.query_node_tile(index)
		if node.y != aimed.y:
			continue
		# A square ring rather than a circle, because the thing being aimed is a
		# rectangle of tiles and "within five tiles" on a grid means five either way.
		var distance: int = maxi(absi(node.x - aimed.x), absi(node.z - aimed.z))
		if distance > MINER_SNAP_RANGE_TILES:
			continue
		if not sim.query_node_yields_for(machine_index, index):
			continue
		if not sim.query_node_is_within_depth_of(machine_index, index):
			# Remembered rather than returned, so a shallow Node further out still wins:
			# the answer to "your Miner cannot lift this" is only worth saying when there
			# is nothing it *can* lift nearby.
			too_deep = true
			continue
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = index

	if nearest == -1:
		placement.aim = Aim.NODE_TOO_DEEP if too_deep else Aim.NO_NODE_IN_RANGE
		return placement

	placement.tile = _centred_on(definition, rotation, sim.query_node_tile(nearest))
	placement.snapped = placement.tile != aimed
	return placement


## Where a Machine would land, aim and snap together. What the controller puts in an
## intent and what the hologram draws, so they cannot disagree.
static func placement(
	sim: Simulation, player_id: int, machine_index: int, rotation: int
) -> Placement:
	return snap_to_a_node(sim, machine_index, rotation, aimed_tile(sim, player_id))


## The footprint anchor that puts a Machine's middle over a tile.
##
## `WorldGrid.rotated_footprint` is the one authority on what turning does to a
## footprint, so this asks it rather than swapping the extents itself. The halving floors,
## which puts an even footprint a half-tile to the low side of the Node — a 2x2 Miner
## anchored *at* the Node, covering it and the tile up and across. That is the right
## answer rather than a rounding artefact: the Node is inside the footprint either way,
## and flooring is the one choice that does not depend on which way the thing is turned.
static func _centred_on(
	definition: MachineDefinition, rotation: int, node: Vector3i
) -> Vector3i:
	var size: Vector2i = WorldGrid.rotated_footprint(
		definition.footprint_x, definition.footprint_z, WorldGrid.wrap_rotation(rotation)
	)
	@warning_ignore("integer_division")
	var offset: Vector3i = Vector3i((size.x - 1) / 2, 0, (size.y - 1) / 2)
	return node - offset


## What to tell a player about an aim the Build Gun will not place from.
##
## Here rather than in `refusal_text` because an `Aim` is not a `Refusal`: the wording
## lives beside the enum it is about, and both of these sentences are about the ground
## rather than about the Machine. Silence is the failure this exists to prevent, which is
## the same reason `refusal_text` has a default arm.
static func aim_text(aim: int) -> String:
	match aim:
		Aim.ON_TARGET:
			return ""
		Aim.NO_NODE_IN_RANGE:
			return "no ore in range — a Miner has to stand on a Node"
		Aim.NODE_TOO_DEEP:
			return "that seam is too deep for this Miner"
		_:
			return "cannot build there"


## How high up a Machine's body a hand tool is aimed at, in metres. Half a storey: a
## Smelter is three tiles across and stands about that tall, so this is roughly the middle
## of the thing a player is looking at when they walk up to it.
const TOOL_PLANE_METRES: float = 2.0


## The tile a player's hand tool — the Pneumatic Wrench — is aimed at.
##
## Not the same aim as the Build Gun's, and the difference is the plane. A hologram snaps
## to the floor, so `aimed_tile` crosses the ground; a wrench is held against a Machine's
## *body*, and a player standing at a Smelter is looking several metres up. Aiming a
## wrench down the ground plane means looking at your own feet to repair something at eye
## level, which reads as the tool being broken.
##
## Reach is the Build Gun's rather than the wrench's, deliberately: this is where the
## player is *pointing*, and whether that is close enough to mend is the Simulation's
## decision (`Refusal.OUT_OF_REACH`, from `wrench.reach_metres`). One authority for the
## rule, and an aim that can point past it so the HUD has something to refuse.
static func aimed_tool_tile(sim: Simulation, player_id: int) -> Vector3i:
	var ground: FixedVec2 = sim.query_player_camera_ground_metres(player_id)
	var camera: Vector3 = Vector3(
		Fixed.to_float(ground.x),
		Fixed.to_float(sim.query_player_camera_height_metres(player_id)),
		Fixed.to_float(ground.z)
	)
	var forward: Vector3 = InputQuantiser.forward_vector(
		sim.query_player_yaw_turns(player_id), sim.query_player_camera_pitch_turns(player_id)
	)
	return InputQuantiser.aimed_tile_at_height(
		camera,
		forward,
		TOOL_PLANE_METRES,
		REACH_METRES,
		Fixed.to_float(sim.query_tile_size_metres())
	)


## What to show a player when a placement is refused.
##
## The wording lives on this side of the boundary and the *rule* lives in the Simulation,
## which is the right way round: `Simulation.Refusal` is a fact about the world and this
## is a sentence about it. A reason nobody has written a sentence for still says
## something, because silence is the failure this exists to prevent.
static func refusal_text(refusal: int) -> String:
	match refusal:
		Simulation.Refusal.NONE:
			return ""
		Simulation.Refusal.NO_SUCH_MACHINE:
			return "nothing on the Build Gun"
		Simulation.Refusal.OFF_THE_MAP:
			return "cannot build there — off the Map"
		Simulation.Refusal.OCCUPIED:
			return "cannot build there — something is already standing"
		Simulation.Refusal.MISSING_MATERIALS:
			return "not enough materials"
		Simulation.Refusal.NOTHING_THERE:
			return "nothing there to demolish"
		Simulation.Refusal.CONTENT_IS_LOCKED:
			return "not unlocked — deliver to the Nest"
		Simulation.Refusal.NOT_DAMAGED:
			return "already whole"
		Simulation.Refusal.OUT_OF_REACH:
			return "too far to reach — the wrench is melee"
		Simulation.Refusal.RUN_IS_OVER:
			return "the Run is over"
		Simulation.Refusal.PLAYER_IS_DOWN:
			return "you are down"
		Simulation.Refusal.NO_WEAPON:
			return "nothing in your hands"
		Simulation.Refusal.OUT_OF_AMMUNITION:
			return "DRY — no Ammunition"
		Simulation.Refusal.WEAPON_NOT_READY:
			return ""
		Simulation.Refusal.NO_SUCH_GEAR:
			return "no such Gear"
		Simulation.Refusal.GEAR_IS_LOCKED:
			return "Gear not unlocked — deliver to the Nest"
		Simulation.Refusal.WRONG_SLOT:
			return "that does not fit there"
		Simulation.Refusal.NOTHING_TO_REVIVE:
			return "nobody to pick up"
		Simulation.Refusal.NO_TEAMMATE:
			return "nobody else is here"
		_:
			return "cannot build there"
