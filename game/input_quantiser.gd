## The float-to-fixed boundary. The only place in the project where a float device
## reading becomes a Simulation quantity.
##
## `Fixed.to_float` is the sanctioned crossing *outward*, at the rendering boundary, and
## ADR 0002 says nothing ever converts a float back into a Simulation quantity — because
## the moment a float influences Simulation state, lockstep determinism is gone. A
## first-person controller cannot quite honour that literally: a mouse reports pixels of
## travel as floats, and a camera ray is float arithmetic by nature. So the crossing is
## made exactly once, here, under three rules:
##
## 1. **It lives in `game/`, never in `sim/`.** The purity lint forbids a float inside
##    the Simulation and takes no exemption for this file, because this file is not in
##    the Simulation.
## 2. **What crosses is an integer intent, never a float.** A mouse reading becomes a
##    floored fixed-point count of pixels; a camera ray becomes a whole tile. Both go
##    into an Input Action, which is integers all the way down, so a replay reproduces
##    the intent without ever reproducing the float.
## 3. **Flooring, clamping and NAN-guarding are explicit.** Every conversion floors
##    toward negative infinity, matching `Fixed`, so the sign of a reading never changes
##    the rule applied to it. Every conversion is bounded, because an unbounded intent
##    is an unbounded turn. NAN and INF are reduced to nothing and to the bound, because
##    NAN compares false against everything and an unguarded cast would let it through as
##    an arbitrary integer.
##
## What is deliberately *not* here: the sensitivity that turns pixels into an angle, and
## the speed that turns a throttle into metres. Both are tuning the Simulation owns. This
## module converts a reading; it never decides what the reading means.
class_name InputQuantiser
extends RefCounted

## The layer building happens on. Flat building, per DESIGN.md, so the Build Gun aims at
## the ground and nothing else.
const GROUND_LAYER: int = 0

## How nearly level a ray may be before it is treated as never meeting the ground.
## Without this, a ray a millionth of a degree below level would report a ground hit
## kilometres away.
const LEVEL_EPSILON: float = 0.0001


## A count of pixels of mouse travel as a fixed-point quantity, floored and clamped to
## what a `LOOK` action will carry.
static func pixels_to_fixed(pixels: float) -> int:
	if is_nan(pixels):
		return 0
	var scaled: float = pixels * float(Fixed.ONE)
	if scaled >= float(InputAction.MAX_LOOK_PIXELS):
		return InputAction.MAX_LOOK_PIXELS
	if scaled <= float(-InputAction.MAX_LOOK_PIXELS):
		return -InputAction.MAX_LOOK_PIXELS
	return floori(scaled)


## A throttle in [-1, 1] as a fixed-point quantity, floored and clamped to full.
##
## Separate from `pixels_to_fixed` because it is a different kind of reading with a
## different bound: a throttle is a fraction of full effort and saturates at one, where
## mouse travel is a count that can legitimately be large. Keys produce exactly -1, 0 or
## 1 today, so this is exact; it exists in float form so that an analogue stick is a
## change to the caller and not to the boundary.
static func throttle_to_fixed(throttle: float) -> int:
	if is_nan(throttle):
		return 0
	return Fixed.clamp_fixed(floori(clampf(throttle, -1.0, 1.0) * float(Fixed.ONE)), -Fixed.ONE, Fixed.ONE)


## The tile the Build Gun is aimed at: where the camera ray meets the ground, pulled
## back to within `reach_metres` of the player if the ray lands further away than that.
##
## Reach is clamped *horizontally, from the player*, rather than along the ray. That
## distinction is what makes the Build Gun work in Survey View: from 26 m up at a steep
## tilt the ground is nearly 30 m along the ray but only about 10 m ahead of the player,
## and clamping along the ray would leave the hologram hanging in mid-air six metres in
## front of them instead of under the camera where they are looking.
##
## Reach is an *aiming* limit rather than a rule of the Simulation. It keeps the hologram
## on screen and within arm's length of the Factory a player is working on, which is what
## it is for; making it authoritative is a check in `_build_refusal` and a refusal code,
## and belongs to whoever decides how far a Build Gun should carry.
static func aimed_tile(
	camera: Vector3, forward: Vector3, reach_metres: float, tile_size_metres: float
) -> Vector3i:
	var direction: Vector3 = forward.normalized()
	var ground: float = float(GROUND_LAYER) * float(WorldGrid.STOREY_HEIGHT_METRES)
	var reach: float = maxf(reach_metres, 0.0)

	var offset: Vector2 = Vector2.ZERO
	if direction.y < -LEVEL_EPSILON:
		# The ray meets the ground. Where, measured from directly below the camera.
		var distance: float = (camera.y - ground) / -direction.y
		offset = Vector2(direction.x, direction.z) * distance
	else:
		# A level or upward ray never meets the ground, so the hologram sits at the
		# limit of reach ahead of the player rather than at infinity.
		var level: Vector2 = Vector2(direction.x, direction.z)
		if level.length() > LEVEL_EPSILON:
			offset = level.normalized() * reach

	if offset.length() > reach:
		offset = offset.normalized() * reach

	var size: float = maxf(tile_size_metres, LEVEL_EPSILON)
	return Vector3i(
		floori((camera.x + offset.x) / size), GROUND_LAYER, floori((camera.z + offset.y) / size)
	)


## The tile a hand tool is aimed at: where the camera ray crosses a horizontal plane at
## `plane_height_metres`, pulled back to within `reach_metres` of the player.
##
## `aimed_tile` above is the Build Gun's aim and only ever looks at the *ground*, because
## building is flat and a hologram snaps to a floor tile. A wrench does not: a player
## standing at a Smelter is looking at its body, several metres up, and a ground-plane ray
## from that angle lands somewhere behind the Machine or nowhere at all. So this is the
## same crossing against a different plane — the waist height of the Factory rather than
## its floor — and it is what the Pneumatic Wrench's repair aims through.
##
## Here rather than at the call site for the reason the whole module exists: a conversion
## written where it is needed is a conversion nobody has tested, and this one has the same
## three obligations as the rest of this file. It floors toward negative infinity, it is
## bounded by reach, and a ray that never meets the plane lands at the limit of reach
## ahead of the player instead of at infinity.
##
## **Nothing about firing crosses here, and that is deliberate.** A round goes where the
## player is aiming, and where the player is aiming is already authoritative fixed-point
## Simulation state — `_player_yaw` and `_player_pitch`, put there by the quantised `LOOK`
## intent. A tile or a direction carried in a `FIRE` action would be a *second* opinion
## about the aim, derived from a float, and in lockstep the second opinion is the one that
## diverges. See `InputAction.Kind.FIRE`.
static func aimed_tile_at_height(
	camera: Vector3,
	forward: Vector3,
	plane_height_metres: float,
	reach_metres: float,
	tile_size_metres: float
) -> Vector3i:
	var direction: Vector3 = forward.normalized()
	var reach: float = maxf(reach_metres, 0.0)
	var plane: float = plane_height_metres
	if is_nan(plane) or is_inf(plane):
		plane = 0.0

	var offset: Vector2 = Vector2.ZERO
	var level: Vector2 = Vector2(direction.x, direction.z)
	var gap: float = camera.y - plane
	# Towards the plane and not already level with it. A ray going the other way, or one
	# so nearly parallel that it would meet the plane kilometres away, falls through to
	# the reach-limited answer below.
	if absf(direction.y) > LEVEL_EPSILON and gap * direction.y < 0.0:
		offset = level * (gap / -direction.y)
	elif level.length() > LEVEL_EPSILON:
		offset = level.normalized() * reach

	if offset.length() > reach:
		offset = offset.normalized() * reach

	var size: float = maxf(tile_size_metres, LEVEL_EPSILON)
	return Vector3i(
		floori((camera.x + offset.x) / size), GROUND_LAYER, floori((camera.z + offset.y) / size)
	)


## Which way a camera is pointing, from the yaw and pitch the Simulation is holding.
##
## Outbound, so it is an ordinary use of `Fixed.to_float`: the angles are authoritative
## fixed-point state and this turns them into the vector a camera and a ray want. Nothing
## reads a float back in — `aimed_tile` takes what comes out of here and returns an
## integer tile.
static func forward_vector(yaw_turns: int, pitch_turns: int) -> Vector3:
	var yaw: float = Fixed.to_float(yaw_turns) * TAU
	var pitch: float = Fixed.to_float(pitch_turns) * TAU
	# Godot's convention: at yaw 0 forward is -z, and a positive yaw rotates it left.
	return Vector3(
		-sin(yaw) * cos(pitch),
		sin(pitch),
		-cos(yaw) * cos(pitch)
	).normalized()
