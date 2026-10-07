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
	## Movement intent. args = [intent_x, intent_z], fixed-point, each clamped to
	## [-ONE, ONE]. A direction and throttle, not a destination — the Simulation
	## owns speed, so a client cannot move faster by sending a larger number.
	MOVE = 1,
}

var kind: Kind = Kind.NONE
var player_id: int = 0
var args: PackedInt64Array = PackedInt64Array()


func _init(action_kind: Kind = Kind.NONE, acting_player: int = 0, action_args: PackedInt64Array = PackedInt64Array()) -> void:
	kind = action_kind
	player_id = acting_player
	args = action_args


static func none(acting_player: int = 0) -> InputAction:
	return InputAction.new(Kind.NONE, acting_player)


static func move(acting_player: int, intent_x: int, intent_z: int) -> InputAction:
	return InputAction.new(
		Kind.MOVE,
		acting_player,
		PackedInt64Array([
			Fixed.clamp_fixed(intent_x, -Fixed.ONE, Fixed.ONE),
			Fixed.clamp_fixed(intent_z, -Fixed.ONE, Fixed.ONE),
		])
	)


## Fixed-point movement intent along x. Zero for any other kind.
func move_intent_x() -> int:
	return _arg(0)


## Fixed-point movement intent along z. Zero for any other kind.
func move_intent_z() -> int:
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


func duplicate_action() -> InputAction:
	return InputAction.new(kind, player_id, args.duplicate())


## A missing argument reads as zero rather than crashing. A malformed action
## should degrade to a no-op, because in lockstep a crash takes down the Run.
func _arg(index: int) -> int:
	if index < 0 or index >= args.size():
		return 0
	return args[index]


func _to_string() -> String:
	var kind_name: String = Kind.keys()[kind]  # purity-ok: enum keys are declaration-ordered
	return "InputAction(%s, player %d, %s)" % [kind_name, player_id, args]
