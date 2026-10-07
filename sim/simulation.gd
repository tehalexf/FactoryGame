## The Simulation: the whole authoritative game state, and the project's only
## test seam.
##
## Its entire surface is three things:
##
##     step(actions)    advance exactly one tick
##     hash()           reduce the whole state to one integer
##     query_*(...)     read-only projections
##
## Nothing else gets to touch state. The Godot-side layer turns devices into
## Input Actions, calls `step`, and draws what the queries return — it holds no
## authoritative state of its own, which is what keeps the seam count at one
## (ADR 0001). Later tickets add the modules behind this façade — grid, Belts,
## Machines, Power, Heat, Waves, Turrets, Silo, Delivery — and they are all
## tested through these same three entry points, never directly.
##
## The rules every line behind this façade obeys, from ADR 0002:
##
## * Fixed-point integers only. No floats, in state or in intermediate steps.
## * No wall-clock time. The Simulation has no idea how long a tick took; it only
##   knows which tick it is on. Deciding *when* to step is the caller's business.
##   `TICKS_PER_SECOND` is a conversion rate for tuning values, not a clock.
## * No unseeded randomness. `DeterministicRng`, seeded at construction, is the
##   only source, and its state is part of the hash.
## * No iteration over an unordered collection. Arrays indexed by id, in index
##   order. Where a Dictionary is unavoidable, its keys get sorted first.
##
## `tests/cases/test_simulation_purity.gd` enforces all four against the source of
## every file in this directory, so a later ticket cannot quietly break one.
class_name Simulation
extends RefCounted

## Simulation ticks per second of game time. Fixed, because a variable tick rate
## would make the Simulation depend on real time. Rates expressed per second in
## tuning files are converted with this.
const TICKS_PER_SECOND: int = 60

## How fast a player walks, in metres per second.
const PLAYER_SPEED_METRES_PER_SECOND: int = 4

# ── State ─────────────────────────────────────────────────────────────────────
# Everything below is authoritative, fed into the hash in a fixed order, and
# data-oriented: parallel arrays indexed by id rather than objects in a graph.

var _tick: int = 0
var _seed: int = 0
var _rng: DeterministicRng = null

## Player positions in fixed-point metres, indexed by player id.
var _player_x: PackedInt64Array = PackedInt64Array()
var _player_z: PackedInt64Array = PackedInt64Array()


## Builds a Simulation. Two built with the same arguments are indistinguishable,
## which is the property the determinism harness rests on.
func _init(world_seed: int = 0, player_count: int = 1) -> void:
	_seed = world_seed
	_rng = DeterministicRng.new(world_seed)

	var players: int = maxi(player_count, 1)
	_player_x.resize(players)
	_player_z.resize(players)
	_player_x.fill(0)
	_player_z.fill(0)


# ── Advancing ─────────────────────────────────────────────────────────────────

## Advances the Simulation by exactly one tick, applying the given Input Actions.
##
## Whole ticks only — there is no partial step and no delta argument. A caller
## that wants to run at a different speed calls this more or less often, and gets
## bit-identical results either way.
##
## Actions are applied in the order given, before the tick's own updates. Lockstep
## requires every client to see the same order, so the caller is responsible for
## ordering them canonically before they get here.
func step(actions: Array) -> void:
	for action: InputAction in actions:
		_apply(action)

	_tick += 1


func _apply(action: InputAction) -> void:
	if action == null:
		return

	match action.kind:
		InputAction.Kind.NONE:
			pass
		InputAction.Kind.MOVE:
			_apply_move(action)


func _apply_move(action: InputAction) -> void:
	if not _is_player(action.player_id):
		return

	# Intent is a direction and throttle; the Simulation owns the speed, so a
	# malformed or hostile client cannot move faster by sending a bigger number.
	var step_size: int = Fixed.from_rational(PLAYER_SPEED_METRES_PER_SECOND, TICKS_PER_SECOND)
	_player_x[action.player_id] += Fixed.mul(action.move_intent_x(), step_size)
	_player_z[action.player_id] += Fixed.mul(action.move_intent_z(), step_size)


# ── Hashing ───────────────────────────────────────────────────────────────────

## Reduces the whole authoritative state to one integer.
##
## A pure read: it never mutates anything, so a test or a desync check can call it
## as often as it likes. Every new piece of state a later ticket adds must be fed
## in here, in a fixed order — state that is not hashed is state whose divergence
## the harness cannot see.
func hash() -> int:
	var hasher: StateHasher = StateHasher.new()
	hasher.feed_int(_tick)
	hasher.feed_int(_seed)
	hasher.feed_int(_rng.state)
	hasher.feed_ints(_player_x)
	hasher.feed_ints(_player_z)
	return hasher.digest()


# ── Queries ───────────────────────────────────────────────────────────────────
# Read-only projections. They copy rather than hand out references, so a caller
# cannot reach through a query and mutate state.

## Which tick the Simulation has completed. A fresh Simulation is on tick 0.
func query_tick() -> int:
	return _tick


## The seed this Simulation was built from.
func query_seed() -> int:
	return _seed


func query_player_count() -> int:
	return _player_x.size()


## A player's position in fixed-point metres. An unknown id reads as the origin
## rather than crashing: in lockstep, a malformed action must degrade, not take
## the Run down.
func query_player_position(player_id: int) -> FixedVec2:
	if not _is_player(player_id):
		return FixedVec2.zero()
	return FixedVec2.new(_player_x[player_id], _player_z[player_id])


func _is_player(player_id: int) -> bool:
	return player_id >= 0 and player_id < _player_x.size()
