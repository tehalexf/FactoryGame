## Where the Build Gun is pointing, and what to tell a player when it refuses.
##
## The tool through which all construction happens, available at all times including
## mid-Wave (GLOSSARY.md). **There is no mode to enter and nothing in the Simulation asks
## whether building is allowed** — but this file is where the one fact about the *input*
## lives, because build mode is what the left mouse button means and that is presentation.
## `hand_refusal` is it, and it is the only thing that returns
## `Refusal.BUILD_GUN_IS_HOLSTERED`: a player holding a rifle builds exactly as well as one
## holding the Build Gun, they just are not doing it with this click.
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


## Why the Build Gun would do nothing at all, whatever it is aimed at, or `Refusal.NONE`.
##
## **The whole of what build mode decides, written once.** #35's playtest found the
## hologram still drawn and still green with a rifle in frame, because the renderer asked
## `query_build_refusal` — which has never heard of the mode and must not — while the
## controller carried four separate inline `and in_build_mode` tests. That is two answers
## to one question, which is the shape `query_build_refusal` exists to prevent.
##
## It takes the mode as an argument rather than reading it, and that is the load-bearing
## detail. `PlayerController` routes by the mode the player will be in once *this tick's*
## `B` has applied, so a player who presses `B` and clicks in the same tick gets the act of
## the mode they are swapping to; the renderer draws the mode the Simulation is holding
## now. Those are different values on exactly one tick in a swap, and both are correct —
## so the rule is a function of the mode and the callers each supply the one they mean.
##
## Nothing in the Simulation is being asked for permission. Building is never gated: an
## `InputAction.build_machine` that reaches the façade is applied whatever is in the
## player's hands (`test_nothing_in_the_simulation_asks_the_mode_for_permission`). What is
## decided here is what one button *means*, which is this layer's job and no one else's.
static func hand_refusal(build_gun_in_hand: bool) -> int:
	if build_gun_in_hand:
		return Simulation.Refusal.NONE
	return Simulation.Refusal.BUILD_GUN_IS_HOLSTERED


## Why a placement would not happen, or `Refusal.NONE`: the hand first, then the
## Simulation's own rule about the tile.
##
## The one function both the hologram and the click go through, so what a player is shown
## and what their click does cannot disagree — the same bargain `query_build_refusal` and
## `_apply_build_machine` already have on the other side of the boundary, extended by the
## one fact that lives on this side.
##
## **The hand is checked before the ground**, for the reason the ground is checked before
## the wallet: what is in your hands is the more immediate fact and the one a player fixes
## with one key.
static func build_refusal(
	sim: Simulation,
	player_id: int,
	build_gun_in_hand: bool,
	machine_index: int,
	tile: Vector3i,
	rotation: int
) -> int:
	var hand: int = hand_refusal(build_gun_in_hand)
	if hand != Simulation.Refusal.NONE:
		return hand
	return sim.query_build_refusal(player_id, machine_index, tile, rotation)


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
		Simulation.Refusal.BUILD_GUN_IS_HOLSTERED:
			# Rarely read, because the hologram is hidden rather than reddened when the
			# gun is away — a promise you cannot see needs no caption. It is here so the
			# reason is never a silence, which is what this function exists to prevent.
			return "the Build Gun is holstered — [B] to draw it"
		_:
			return "cannot build there"
