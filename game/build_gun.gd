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
		_:
			return "cannot build there"
