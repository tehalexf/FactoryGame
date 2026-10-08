## The shape a dragged Belt route takes: which tiles it covers, which runs it breaks
## into, and which way Items travel along each.
##
## Pure arithmetic over tiles, like `WorldGrid` and for the same reason. Three callers
## must agree about a route that does not exist yet — the refusal projection the preview
## reads, the apply that lays it, and the renderer drawing the preview — and a route
## computed three times is three chances to disagree on the frame it matters. So it is
## computed once, here, and all three ask.
##
## **A route is an L: one run, one corner, one run.** One corner per drag rather than a
## general path, because a path a player did not draw is a path they have to inspect
## before committing, and a zigzag is two drags. The corner axis says which leg comes
## first and is carried in the intent, so what a player saw previewed is what crosses.
##
## **The first run stops one tile short of the corner.** A Belt hands its Items to the
## Belt whose run *starts* on the tile past its own far end (`_hand_off`), so the corner
## tile has to be the second run's entry rather than the first run's exit. Getting that
## off by one lays two Belts that look joined and are not, which is exactly the class of
## defect this file exists to have one copy of.
class_name BeltRoute
extends RefCounted

## Travel along x first, then turn and travel along z.
const ALONG_X: int = 0

## Travel along z first, then turn and travel along x.
const ALONG_Z: int = 1


## One straight run of a route: where it starts, where it ends, and the `WorldGrid`
## direction Items travel along it. Both ends are covered by the run.
class Run extends RefCounted:
	var from: Vector3i = Vector3i.ZERO
	var to: Vector3i = Vector3i.ZERO
	var direction: int = 0

	func _init(run_from: Vector3i, run_to: Vector3i, run_direction: int) -> void:
		from = run_from
		to = run_to
		direction = run_direction

	## How many tiles this run covers, counting both ends.
	func length_tiles() -> int:
		return absi(to.x - from.x) + absi(to.z - from.z) + 1

	func _to_string() -> String:
		return "Run(%s → %s, direction %d)" % [from, to, direction]


## The runs a route breaks into, in the order Items travel them: at most two, and empty
## when the two ends do not describe a route at all.
##
## A drag that never moved is **not** a route here, because a one-tile Belt still has to
## be aimed and these two tiles do not say which way. The Simulation resolves that case
## from the player's own facing, which is state it already holds.
static func segments(from: Vector3i, to: Vector3i, corner_axis: int) -> Array:
	var runs: Array = []
	if from.y != to.y:
		return runs
	if from == to:
		return runs

	if from.x == to.x or from.z == to.z:
		runs.append(Run.new(from, to, WorldGrid.direction_from_to(from, to)))
		return runs

	var corner: Vector3i = (
		Vector3i(to.x, from.y, from.z) if corner_axis == ALONG_X
		else Vector3i(from.x, from.y, to.z)
	)
	var first: int = WorldGrid.direction_from_to(from, corner)
	var step: Vector3i = WorldGrid.direction_step(first)
	runs.append(Run.new(from, corner - step, first))
	runs.append(Run.new(corner, to, WorldGrid.direction_from_to(corner, to)))
	return runs


## Every tile a route covers, entry first and no tile twice.
static func tiles(from: Vector3i, to: Vector3i, corner_axis: int) -> Array[Vector3i]:
	var covered: Array[Vector3i] = []
	for run: Run in segments(from, to, corner_axis):
		var step: Vector3i = WorldGrid.direction_step(run.direction)
		for offset: int in range(run.length_tiles()):
			covered.append(run.from + step * offset)
	return covered


## How many tiles of Belt a route is — the number a player reads before committing.
## 0 when the two ends describe no route.
static func length_tiles(from: Vector3i, to: Vector3i, corner_axis: int) -> int:
	var total: int = 0
	for run: Run in segments(from, to, corner_axis):
		total += run.length_tiles()
	return total


## The corner axis a drag from one tile to another most naturally bends on: the longer
## leg first, so a mostly-sideways drag goes sideways before it turns.
##
## Presentation rather than rule — the controller offers it and the player may flip it —
## but it lives here because the preview and the intent must agree about what "the
## default" was, and because it is the same arithmetic the route is.
static func natural_corner_axis(from: Vector3i, to: Vector3i) -> int:
	return ALONG_X if absi(to.x - from.x) >= absi(to.z - from.z) else ALONG_Z
