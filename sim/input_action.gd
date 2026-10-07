## One player intent, and the only thing that may cross the network wire.
##
## ADR 0002 puts the game on deterministic lockstep: clients exchange intents, not
## world state, and each one simulates every tick identically. So an Input Action
## is the sole way anything outside the Simulation can affect what is inside it.
## The Godot-side layer translates devices into these and hands them to `step`;
## it never writes Simulation state itself.
##
## The encoding is deliberately generic — a kind, the player who intended it, and
## an ordered list of integer arguments whose meaning each kind defines. That
## keeps hashing, comparison and (later) serialisation written once, so adding a
## kind never touches this file's plumbing. Build intents, Recipe selections, Silo
## loads and lever pulls all fit the same shape.
##
## Construct these through the named static functions rather than by hand, so
## argument layouts stay in one place.
class_name InputAction
extends RefCounted

enum Kind {
	## Does nothing. Useful as an explicit "this player sent no intent this tick".
	NONE = 0,
	## Movement intent. args = [forward, strafe], fixed-point, each clamped to
	## [-ONE, ONE]. A throttle in the player's *own* frame, not a destination and not
	## a world-space direction: the Simulation owns the walking speed, so a client
	## cannot move faster by sending a larger number, and it owns the yaw the throttle
	## is rotated by, so a client cannot walk somewhere other than where the
	## Simulation says it is facing.
	##
	## Per tick. Sending no `MOVE` is how a player stands still, so an idle tick is a
	## tick spent slowing down rather than one spent coasting on a stale throttle.
	MOVE = 1,
	## Replace the Simulation's content definitions. args = [digest of the new set].
	## The set itself travels in `payload`.
	##
	## A reload is an Input Action rather than a method on the façade for three
	## reasons: it is ordered with every other intent, so the tick it lands on is
	## unambiguous; it appears in a recorded script, so a replay reproduces it; and
	## in co-op it is the Host's intent broadcast like any other, which is where the
	## digest earns its place — every client reloads its own copy of the files, and a
	## client whose copy hashes differently can refuse instead of desyncing silently.
	RELOAD_DEFINITIONS = 2,
	## Build a Machine. args = [machine definition index, tile x, tile y, tile z].
	##
	## The Machine travels as an index into the definition set's sorted Machine ids
	## rather than as a string, because an intent on the wire is integers; the
	## Simulation resolves it to an id at the moment it builds, and holds the id
	## afterwards so a hot-reload that renumbers the table cannot renumber a Factory
	## that is already standing.
	BUILD_MACHINE = 3,
	## Lay a Belt along a straight run of tiles. args = [from x, y, z, to x, y, z].
	##
	## Both ends travel because a Belt is a run rather than a tile: a player drags one
	## out, and sending the whole run as one intent means a dragged Belt either lands
	## or is refused, never half-lands. A run that is not axis-aligned on one layer is
	## refused — there are no diagonal Belts on a 2 m grid (DESIGN.md).
	##
	## No Belt definition index travels. Unlike a Machine, a Belt has no row in
	## `content/machines.csv`: it is not a Machine (GLOSSARY.md keeps the two apart),
	## it runs no Recipe, and its one tier's rating lives in `content/tuning.toml`.
	BUILD_BELT = 4,
	## Mouse look. args = [pixels right, pixels down], fixed-point counts of pixels
	## of mouse travel.
	##
	## Pixels, not an angle: the mouse is the one genuinely continuous device the game
	## reads, and the sensitivity that turns its travel into an angle is a tuning value
	## the Simulation owns — the same arrangement as `MOVE`, where the intent is a
	## throttle and the speed belongs to the Simulation. A client therefore cannot turn
	## faster by sending a bigger number, and the angle a player is facing is
	## authoritative state rather than something the camera remembers.
	##
	## The float-to-fixed crossing happens before this is constructed, in
	## `game/input_quantiser.gd`, which is the only place in the project where a float
	## device reading becomes a Simulation quantity.
	LOOK = 5,
	## Hold or release Survey View. args = [1 while held, 0 once released].
	##
	## Held rather than toggled, and sent every tick it is held, so the camera's
	## position is a function of how long the key has been down rather than of a latch
	## somebody has to remember to clear. It is state in the Simulation because the
	## *transition* is: a lift caught halfway is a different state from one at either
	## end, and the camera is told where to be rather than deciding.
	##
	## This is not a build mode. Building works identically at either height
	## (DESIGN.md, GLOSSARY.md), and nothing in the Simulation consults it to decide
	## whether an intent is allowed.
	SURVEY_VIEW = 6,
}

## Most pixels of mouse travel one `LOOK` action may carry on either axis. Far more
## than any real frame produces at any sensitivity, and finite, which is what matters:
## an unbounded intent is an unbounded turn.
const MAX_LOOK_PIXELS: int = 10000 * Fixed.ONE

var kind: Kind = Kind.NONE
var player_id: int = 0
var args: PackedInt64Array = PackedInt64Array()

## Out-of-band payload, used by `RELOAD_DEFINITIONS` and nothing else. The one
## action whose subject is a blob rather than a handful of integers: a definition
## set is the same kind of thing as the world state transferred on join, not an
## intent. It is not hashed directly — `args[0]` holds its digest, and that is what
## goes into the hash — so the generic encoding above stays the whole wire format.
var payload: RefCounted = null


func _init(action_kind: Kind = Kind.NONE, acting_player: int = 0, action_args: PackedInt64Array = PackedInt64Array()) -> void:
	kind = action_kind
	player_id = acting_player
	args = action_args


static func none(acting_player: int = 0) -> InputAction:
	return InputAction.new(Kind.NONE, acting_player)


## Walks a player. `forward` is positive towards whatever they are looking at and
## `strafe` is positive to their right; both are throttles clamped to full.
static func move(acting_player: int, forward: int, strafe: int) -> InputAction:
	return InputAction.new(
		Kind.MOVE,
		acting_player,
		PackedInt64Array([
			Fixed.clamp_fixed(forward, -Fixed.ONE, Fixed.ONE),
			Fixed.clamp_fixed(strafe, -Fixed.ONE, Fixed.ONE),
		])
	)


## Turns the view by a count of pixels of mouse travel: `pixels_right` turns the
## player clockwise, `pixels_down` pitches the view downward. Both are fixed-point,
## and both are clamped to a sane sweep so a malformed or hostile intent cannot spin
## the view arbitrarily far in one tick.
static func look(acting_player: int, pixels_right: int, pixels_down: int) -> InputAction:
	return InputAction.new(
		Kind.LOOK,
		acting_player,
		PackedInt64Array([
			Fixed.clamp_fixed(pixels_right, -MAX_LOOK_PIXELS, MAX_LOOK_PIXELS),
			Fixed.clamp_fixed(pixels_down, -MAX_LOOK_PIXELS, MAX_LOOK_PIXELS),
		])
	)


## Holds or releases Survey View for a player. Sent every tick the key is held.
static func survey_view(acting_player: int, held: bool) -> InputAction:
	return InputAction.new(
		Kind.SURVEY_VIEW, acting_player, PackedInt64Array([1 if held else 0])
	)


## Replaces the Simulation's content definitions with `definitions`.
##
## The digest goes into `args` so that the action's hash describes the set it
## carries. A Simulation refuses the action if the payload is missing, failed to
## load, or does not hash to the digest claimed here.
static func reload_definitions(acting_player: int, definitions: Definitions) -> InputAction:
	var digest: int = 0 if definitions == null else definitions.digest()
	var action: InputAction = InputAction.new(
		Kind.RELOAD_DEFINITIONS, acting_player, PackedInt64Array([digest])
	)
	action.payload = definitions
	return action


## Builds a Machine at a tile. The tile is the footprint's anchor, and the footprint
## grows along +x and +z from it by whatever `content/machines.csv` says — that file
## is the only authority for a footprint.
static func build_machine(acting_player: int, machine_index: int, tile: Vector3i) -> InputAction:
	return InputAction.new(
		Kind.BUILD_MACHINE,
		acting_player,
		PackedInt64Array([machine_index, tile.x, tile.y, tile.z])
	)


## Lays a Belt along the straight run from one tile to another, both ends included.
## The Items travel from `from_tile` towards `to_tile`, so the aim is also the
## direction of flow.
static func build_belt(acting_player: int, from_tile: Vector3i, to_tile: Vector3i) -> InputAction:
	return InputAction.new(
		Kind.BUILD_BELT,
		acting_player,
		PackedInt64Array([
			from_tile.x, from_tile.y, from_tile.z, to_tile.x, to_tile.y, to_tile.z
		])
	)


## The tile a `BUILD_BELT` action starts its run at — the end Items enter from.
func belt_from_tile() -> Vector3i:
	return Vector3i(_arg(0), _arg(1), _arg(2))


## The tile a `BUILD_BELT` action ends its run at — the end Items leave from.
func belt_to_tile() -> Vector3i:
	return Vector3i(_arg(3), _arg(4), _arg(5))


## The Machine definition index a `BUILD_MACHINE` action names.
func build_machine_index() -> int:
	return _arg(0)


## The tile a `BUILD_MACHINE` action anchors its footprint at.
func build_tile() -> Vector3i:
	return Vector3i(_arg(1), _arg(2), _arg(3))


## The definition set a `RELOAD_DEFINITIONS` action carries, or null.
func reload_payload() -> Definitions:
	if payload is Definitions:
		return payload
	return null


## The digest the action claims its payload has.
func declared_digest() -> int:
	return _arg(0)


## Whether a `SURVEY_VIEW` action is holding the camera up or letting it down.
func survey_is_held() -> bool:
	return _arg(0) != 0


## Pixels of rightward mouse travel a `LOOK` action carries, fixed-point.
func look_pixels_right() -> int:
	return _arg(0)


## Pixels of downward mouse travel a `LOOK` action carries, fixed-point.
func look_pixels_down() -> int:
	return _arg(1)


## Fixed-point forward throttle, positive towards what the player is looking at.
## Zero for any other kind.
func move_intent_forward() -> int:
	return _arg(0)


## Fixed-point strafe throttle, positive to the player's right. Zero for any other
## kind.
func move_intent_strafe() -> int:
	return _arg(1)


## Feeds this action into a hash. Recordings are compared by hash too, so a
## replay cannot quietly be fed different inputs than the ones recorded.
func feed_into(hasher: StateHasher) -> void:
	hasher.feed_int(kind)
	hasher.feed_int(player_id)
	hasher.feed_ints(args)


func equals(other: InputAction) -> bool:
	if other == null:
		return false
	return kind == other.kind and player_id == other.player_id and args == other.args


## A copy. The payload is shared rather than copied, which is safe because a loaded
## definition set is immutable — hot-reload builds a new one instead of editing one.
func duplicate_action() -> InputAction:
	var copy: InputAction = InputAction.new(kind, player_id, args.duplicate())
	copy.payload = payload
	return copy


## A missing argument reads as zero rather than crashing. A malformed action
## should degrade to a no-op, because in lockstep a crash takes down the Run.
func _arg(index: int) -> int:
	if index < 0 or index >= args.size():
		return 0
	return args[index]


func _to_string() -> String:
	var kind_name: String = Kind.keys()[kind]  # purity-ok: enum keys are declaration-ordered
	return "InputAction(%s, player %d, %s)" % [kind_name, player_id, args]
