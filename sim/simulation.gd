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

# Note what is *not* a constant here any more: how fast a player walks. That lives
# in content/tuning.toml, because it is a balance number and balance numbers belong
# to whoever is tuning the game, not to whoever is editing code.

# ── State ─────────────────────────────────────────────────────────────────────
# Everything below is authoritative, fed into the hash in a fixed order, and
# data-oriented: parallel arrays indexed by id rather than objects in a graph.

var _tick: int = 0
var _seed: int = 0
var _rng: DeterministicRng = null

## The content definitions this Run is using: Machines, Recipes, Items and tuning,
## loaded from content/. Immutable — a reload swaps the whole set rather than
## editing it, which is what lets queries hand it out without copying.
var _definitions: Definitions = null

## How many times the definitions have been reloaded mid-Run. Hashed, so reloading
## back to the original files does not restore the earlier hash: the Run did change,
## and a hash that said otherwise could not describe its own history.
var _definition_generation: int = 0

## Player positions in fixed-point metres, indexed by player id.
var _player_x: PackedInt64Array = PackedInt64Array()
var _player_z: PackedInt64Array = PackedInt64Array()

## The Map's Nodes, as parallel arrays in the canonical order `MapLayout` sorted
## them into. None of this changes during a Run: a Node is inexhaustible (DESIGN.md),
## so there is no quantity here to run down and nothing subtracts from one.
var _node_tile_x: PackedInt64Array = PackedInt64Array()
var _node_tile_y: PackedInt64Array = PackedInt64Array()
var _node_tile_z: PackedInt64Array = PackedInt64Array()
var _node_resource: PackedStringArray = PackedStringArray()
var _node_depth: PackedInt64Array = PackedInt64Array()

## The Machines standing in the Factory, in the order they were built. Parallel
## arrays rather than objects, so a tick walks integers in index order.
##
## The *id* is held rather than the definition index, because a hot-reload resorts
## the definition table: a Factory already standing must not be renumbered under its
## own feet. The index is a wire detail of the build intent and nothing more.
var _machine_id: PackedStringArray = PackedStringArray()
var _machine_tile_x: PackedInt64Array = PackedInt64Array()
var _machine_tile_y: PackedInt64Array = PackedInt64Array()
var _machine_tile_z: PackedInt64Array = PackedInt64Array()

## The tick each Machine was placed on. A Machine does not run on the tick it was
## built: it was placed during that tick, and crediting it a full tick of work for
## the instant it appeared would make a Machine's first output land a tick early.
## Also what a later ticket needs to show a Machine's age.
var _machine_built_tick: PackedInt64Array = PackedInt64Array()

## Ticks accumulated towards the current craft, per Machine. Ticks rather than a
## fixed-point fraction: a craft takes a whole number of ticks, so counting them is
## exact and no rounding accumulates over a 40-hour Run.
var _machine_progress_ticks: PackedInt64Array = PackedInt64Array()

## What each Machine is holding, as one sorted `PackedStringArray` of Item ids and
## one matching `PackedInt64Array` of counts per Machine. Item *ids*, not interned
## indices, so a hot-reload that changes the Item set cannot silently relabel a
## buffer. Sorted, so iteration order is a property of the content rather than of
## the order things happened to be produced in.
##
## This is a Machine's own output buffer, the one a Belt loading from its output port
## drains. Uncapped: a producer whose chest fills is a Power-and-Heat-era concern, and the
## back-pressure a player diagnoses is the Belt backing up, not the Miner.
var _machine_buffer_items: Array = []
var _machine_buffer_counts: Array = []

## The Belts in the Factory, in the order they were laid. A Belt is a straight run of
## tiles anchored at the end Items *enter* from, running `tiles` tiles along
## `direction`; the far end is where Items leave. Belts are not Machines (GLOSSARY.md
## keeps the two apart) and have no row in `content/machines.csv`.
var _belt_tile_x: PackedInt64Array = PackedInt64Array()
var _belt_tile_y: PackedInt64Array = PackedInt64Array()
var _belt_tile_z: PackedInt64Array = PackedInt64Array()
var _belt_direction: PackedInt64Array = PackedInt64Array()
var _belt_tiles: PackedInt64Array = PackedInt64Array()

## The Items riding each Belt: one `PackedStringArray` of Item ids and one matching
## `PackedInt64Array` of positions per Belt, ordered front first — the Item nearest the
## far end is slot 0. Arrays of integers rather than an object per Item, because this
## is the system that dominates a late-game frame and an Item is a position and an id
## and nothing else.
##
## A position is a whole number of *sub-units* along the run, not a fixed-point
## distance. Sub-units are sized so that an Item advances exactly one of them per tick
## (see `_belt_subunits_per_tile`), which is what makes throughput an exact function of
## the rating in `content/tuning.toml` rather than something that emerges from
## rounding. Metres are computed only on the way out, for the renderer.
##
## Item *ids* rather than interned Item indices, for the reason a Machine's buffer
## holds ids: a hot-reload resorts the Item set, and relabelling the ore already on a
## Belt would be a silent corruption.
var _belt_item_ids: Array = []
var _belt_item_offsets: Array = []

## The order the Belts are advanced in each tick, and the answer to the one question
## this system cannot dodge: updating Belts in index order would make a line's
## throughput depend on the order it was built in, because a Belt that runs after the
## Belt it feeds sees a slot that has already been vacated while one that runs before
## it does not.
##
## So index order is not used. Each tick walks the Belts **downstream first**: a Belt
## is advanced only after the Belt it hands Items to has been. Chains are followed
## from a canonical starting order — by the entry tile of the run, which is geography
## and not history — and a Belt loop, which has no downstream-most member, is broken at
## its canonically first Belt. Where two Belts merge into one, priority therefore goes to
## whichever starts at the lower tile, rather than to whichever was laid first.
##
## Derived, not authoritative: a pure function of where the Belts are, so it is rebuilt
## rather than hashed. Rebuilt only when a Belt is laid, because nothing else can change
## which Belt feeds which.
var _belt_update_order: PackedInt64Array = PackedInt64Array()
var _belt_update_order_stale: bool = true

## What each Machine is holding *for* its Recipe, as the same sorted id/count pair as
## the output buffer. A Belt fills this; crafting empties it. Its capacity is what
## back-pressure pushes against: when it is full the Belt feeding it cannot hand over,
## so the Belt fills and stalls where a player can see it.
var _machine_input_items: Array = []
var _machine_input_counts: Array = []


## Builds a Simulation. Two built with the same arguments are indistinguishable,
## which is the property the determinism harness rests on — and that now includes
## the definitions, so "the same arguments" means the same content files too.
##
## Passing no definitions loads the shipped content. A set that failed to load is
## kept as-is rather than replaced by a working-looking default: the errors are
## pushed where a developer will see them, `query_definitions_loaded` reports false,
## and the Godot layer refuses to start a Run. A Simulation that silently invented
## numbers to stay runnable would be worse than one that does nothing.
func _init(
	world_seed: int = 0,
	player_count: int = 1,
	definitions: Definitions = null,
	map_layout: MapLayout = null
) -> void:
	_seed = world_seed
	_rng = DeterministicRng.new(world_seed)

	_definitions = definitions
	if _definitions == null:
		_definitions = Definitions.load_from_directory(Definitions.CONTENT_DIR)
	if _definitions.has_errors():
		push_error("content definitions failed to load:\n%s" % _definitions.describe_errors())

	var layout: MapLayout = map_layout
	if layout == null:
		layout = MapLayout.starter()
	_node_tile_x = layout.node_tile_x.duplicate()
	_node_tile_y = layout.node_tile_y.duplicate()
	_node_tile_z = layout.node_tile_z.duplicate()
	_node_resource = layout.node_resource.duplicate()
	_node_depth = layout.node_depth.duplicate()

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

	_transport()
	_extract()
	_craft()

	_tick += 1


func _apply(action: InputAction) -> void:
	if action == null:
		return

	match action.kind:
		InputAction.Kind.NONE:
			pass
		InputAction.Kind.MOVE:
			_apply_move(action)
		InputAction.Kind.RELOAD_DEFINITIONS:
			_apply_reload_definitions(action)
		InputAction.Kind.BUILD_MACHINE:
			_apply_build_machine(action)
		InputAction.Kind.BUILD_BELT:
			_apply_build_belt(action)


func _apply_move(action: InputAction) -> void:
	if not _is_player(action.player_id):
		return

	# Intent is a direction and throttle; the Simulation owns the speed, so a
	# malformed or hostile client cannot move faster by sending a bigger number. The
	# speed itself comes from tuning, so it is a number in a file rather than a
	# number in this line.
	var step_size: int = Fixed.div(
		_definitions.player_walk_speed, Fixed.from_int(TICKS_PER_SECOND)
	)
	_player_x[action.player_id] += Fixed.mul(action.move_intent_x(), step_size)
	_player_z[action.player_id] += Fixed.mul(action.move_intent_z(), step_size)


# ── Transport ─────────────────────────────────────────────────────────────────

## Advances every Belt by one tick: hand off what has reached the far end, carry
## everything forward, then take one more Item from the Machine port behind.
##
## The Belts are walked **downstream first** (`_belt_update_order`), never in index
## order, so a line's behaviour is a function of its geography and not of the order its
## Belts happened to be laid in.
##
## Belts run before Machines in a tick, so an Item delivered into a Machine's input
## buffer is available to that Machine's craft the same tick, while an Item a Machine
## has just produced waits for the next tick before a Belt collects it — the same
## "placed this tick does not act this tick" rule a freshly built Machine follows.
func _transport() -> void:
	var order: PackedInt64Array = _ordered_belts()
	for position: int in range(order.size()):
		_advance_belt(order[position])


## One Belt, one tick.
##
## Items are held nose to tail, slot 0 nearest the far end, and each one advances
## exactly one sub-unit unless the Item ahead of it — or the end of the run — is in the
## way. That clamp is the whole of back-pressure: nothing is special-cased for a full
## Belt, Items simply pack at their spacing behind whatever has stopped, and the queue
## that forms is the queue the player sees.
func _advance_belt(index: int) -> void:
	var spacing: int = _belt_spacing_subunits()
	var front: int = _belt_front_offset(index)
	var items: PackedStringArray = _belt_item_ids[index]
	var offsets: PackedInt64Array = _belt_item_offsets[index]

	if offsets.size() > 0 and offsets[0] >= front and _hand_off(index, items[0]):
		items.remove_at(0)
		offsets.remove_at(0)

	for slot: int in range(offsets.size()):
		var limit: int = front if slot == 0 else offsets[slot - 1] - spacing
		offsets[slot] = mini(offsets[slot] + 1, limit)

	_belt_item_ids[index] = items
	_belt_item_offsets[index] = offsets

	_load_from_port(index)


## Hands the leading Item off the far end of a Belt, reporting whether it went.
##
## The far end feeds whatever is on the next tile: a Machine's input port, or another
## Belt that *starts* there. A Belt merely passing through that tile is not a
## connection — side-loading onto the middle of a Belt does not exist yet, and a silent
## one would make a line's throughput unexplainable.
##
## Refused when the destination cannot take the Item: a full input buffer, a Machine
## whose Recipe does not want it, a Miner (whose input is the ground), a Belt with no
## room at its entry, or nothing at all. A refusal leaves the Item exactly where it is,
## which is what makes a blockage visible from the outside.
func _hand_off(index: int, item_id: String) -> bool:
	var beyond: Vector3i = (
		_belt_exit_tile(index) + WorldGrid.direction_step(_belt_direction[index])
	)

	var machine: int = query_machine_at_tile(beyond)
	if machine != -1:
		return _accept_input(machine, item_id)

	var onward: int = _belt_entered_at(beyond)
	if onward == -1 or not _belt_has_entry_room(onward):
		return false
	_place_on_belt(onward, item_id)
	return true


## Whether a Belt's leading Item has reached the far end and cannot get off it.
##
## The pure twin of `_hand_off`: it asks the destination the same question without moving
## anything, which is what lets a query report a blockage rather than the renderer
## guessing one from a count that stopped changing.
func _hand_off_blocked(index: int) -> bool:
	var items: PackedStringArray = _belt_item_ids[index]
	if items.is_empty():
		return false
	var offsets: PackedInt64Array = _belt_item_offsets[index]
	if offsets[0] < _belt_front_offset(index):
		return false

	var beyond: Vector3i = (
		_belt_exit_tile(index) + WorldGrid.direction_step(_belt_direction[index])
	)
	var machine: int = query_machine_at_tile(beyond)
	if machine != -1:
		return not _input_has_room(machine, items[0])

	var onward: int = _belt_entered_at(beyond)
	return onward == -1 or not _belt_has_entry_room(onward)


## Takes one Item from the Machine output port a Belt runs out of, if there is one and
## there is room at the Belt's entry.
##
## The port is the Machine footprint tile the run starts against: Belts connect straight
## into Machine ports and no inserter entity exists (DESIGN.md). The room check is what
## rate-limits loading — an Item can only enter once the last one is a full spacing
## clear, which is exactly the Belt's rated throughput and not a second number that
## could disagree with it.
##
## Which Item, when a Machine holds several: the first in its sorted buffer. Sorted by
## id, so the choice is a property of the content rather than of what was produced
## first.
func _load_from_port(index: int) -> void:
	if not _belt_has_entry_room(index):
		return

	var behind: Vector3i = (
		_belt_entry_tile(index) - WorldGrid.direction_step(_belt_direction[index])
	)
	var machine: int = query_machine_at_tile(behind)
	if machine == -1:
		return

	var items: PackedStringArray = _machine_buffer_items[machine]
	if items.is_empty():
		return
	var item_id: String = items[0]
	_take_from_output(machine, item_id, 1)
	_place_on_belt(index, item_id)


## Whether a Belt has room for another Item at its entry end. True when the hindmost
## Item is at least one spacing clear of the entry, so Items never overlap and a Belt
## never holds more than its capacity.
func _belt_has_entry_room(index: int) -> bool:
	var offsets: PackedInt64Array = _belt_item_offsets[index]
	if offsets.is_empty():
		return true
	return offsets[offsets.size() - 1] >= _belt_spacing_subunits()


## Puts an Item on at the entry end of a Belt. The caller has already established there
## is room.
func _place_on_belt(index: int, item_id: String) -> void:
	var items: PackedStringArray = _belt_item_ids[index]
	var offsets: PackedInt64Array = _belt_item_offsets[index]
	items.append(item_id)
	offsets.append(0)
	_belt_item_ids[index] = items
	_belt_item_offsets[index] = offsets


# ── Belt geometry ─────────────────────────────────────────────────────────────
# A Belt's lane is measured in sub-units, sized so that an Item advances exactly one
# per tick. That is what makes throughput exact: one Item leaves a saturated Belt every
# `ticks_per_item` ticks because the spacing between Items is exactly that many
# sub-units, and no rounding enters anywhere. Metres appear only in the queries.

## How many ticks pass between one Item and the next on a saturated Belt. Floored from
## the rating in tuning, and never less than one — a Belt that moved an Item in no time
## would have infinite throughput.
func _belt_ticks_per_item() -> int:
	if _definitions.belt_items_per_second <= 0:
		return 1
	var exact: int = Fixed.div(
		Fixed.from_int(TICKS_PER_SECOND), _definitions.belt_items_per_second
	)
	return maxi(Fixed.floor_to_int(exact), 1)


## How many Items fit on one tile of Belt.
func _belt_items_per_tile() -> int:
	return maxi(_definitions.belt_items_per_tile, 1)


## Sub-units in one tile of Belt. One Item's spacing is `_belt_ticks_per_item()`
## sub-units, and a tile holds `_belt_items_per_tile()` of them.
func _belt_subunits_per_tile() -> int:
	return _belt_items_per_tile() * _belt_ticks_per_item()


## How far apart Items sit on a Belt, in sub-units. Equal to the ticks per Item, which
## is the identity that makes a saturated Belt deliver at exactly its rating.
func _belt_spacing_subunits() -> int:
	return _belt_ticks_per_item()


## The whole length of a Belt's lane in sub-units.
func _belt_lane_subunits(index: int) -> int:
	return _belt_tiles[index] * _belt_subunits_per_tile()


## The furthest an Item can get along a Belt: one spacing short of the end, because an
## Item occupies a spacing's worth of lane rather than a point.
func _belt_front_offset(index: int) -> int:
	return _belt_lane_subunits(index) - _belt_spacing_subunits()


## The last tile of a Belt's run — the end Items leave from.
func _belt_exit_tile(index: int) -> Vector3i:
	return (
		_belt_entry_tile(index)
		+ WorldGrid.direction_step(_belt_direction[index]) * (_belt_tiles[index] - 1)
	)


## The Belt whose run *starts* on a tile, or -1. What a hand-off looks for, so that only
## an end-to-end join counts as a connection.
func _belt_entered_at(tile: Vector3i) -> int:
	for index: int in range(query_belt_count()):
		if _belt_entry_tile(index) == tile:
			return index
	return -1


## The Belt a Belt hands its Items to, or -1 when its far end feeds a Machine or
## nothing. At most one, which is what keeps the update order a chase down each chain
## rather than a general topological sort.
func _belt_downstream(index: int) -> int:
	var beyond: Vector3i = (
		_belt_exit_tile(index) + WorldGrid.direction_step(_belt_direction[index])
	)
	if query_machine_at_tile(beyond) != -1:
		return -1
	return _belt_entered_at(beyond)


## Converts a position along a Belt to fixed-point metres.
##
## Takes *twice* the sub-unit count, so that an Item's centre — half a spacing past its
## own position — stays a whole number of half-sub-units and the single division below
## is the only rounding in the whole conversion. Dividing once, at the end, is what
## keeps a 500-tile Belt's far end at exactly 1000 m rather than 999.98 m.
func _subunits_to_metres(doubled_subunits: int) -> int:
	return Fixed.div(
		Fixed.from_int(doubled_subunits * WorldGrid.TILE_SIZE_METRES),
		Fixed.from_int(2 * _belt_subunits_per_tile())
	)


# ── Belt update order ─────────────────────────────────────────────────────────

## The order this tick advances the Belts in, downstream first.
func _ordered_belts() -> PackedInt64Array:
	if _belt_update_order_stale:
		_rebuild_belt_update_order()
	return _belt_update_order


## Rebuilds the downstream-first order.
##
## Each Belt feeds at most one other, so the graph is a set of chains and loops rather
## than an arbitrary one, and the order falls out of walking each chain to its end and
## recording it backwards. Chains are started in canonical tile order, so the result is
## a function of where the Belts are. A loop — every member feeding another member — is
## entered at its canonically first Belt and that is where the cycle is cut; one join in
## a Belt loop therefore carries a tick of latency, which is the price of a loop having
## no downstream-most member to start from.
func _rebuild_belt_update_order() -> void:
	var count: int = query_belt_count()
	var starts: Array = []
	for index: int in range(count):
		starts.append(index)
	starts.sort_custom(func(a: int, b: int) -> bool: return _belt_precedes(a, b))

	# 0 not reached, 1 on the chain being walked, 2 placed in the order.
	var visited: PackedInt64Array = PackedInt64Array()
	visited.resize(count)
	visited.fill(0)

	var order: PackedInt64Array = PackedInt64Array()
	for start: int in starts:
		if visited[start] != 0:
			continue
		var chain: PackedInt64Array = PackedInt64Array()
		var current: int = start
		while current != -1 and visited[current] == 0:
			visited[current] = 1
			chain.append(current)
			current = _belt_downstream(current)
		for position: int in range(chain.size() - 1, -1, -1):
			visited[chain[position]] = 2
			order.append(chain[position])

	_belt_update_order = order
	_belt_update_order_stale = false


## Canonical order over Belts: by the tile their run starts at, layer then x then z.
## Geography, so it cannot depend on build order. Total, because no two Belts share a
## tile.
func _belt_precedes(a: int, b: int) -> bool:
	if _belt_tile_y[a] != _belt_tile_y[b]:
		return _belt_tile_y[a] < _belt_tile_y[b]
	if _belt_tile_x[a] != _belt_tile_x[b]:
		return _belt_tile_x[a] < _belt_tile_x[b]
	return _belt_tile_z[a] < _belt_tile_z[b]


# ── Extraction ────────────────────────────────────────────────────────────────

## Advances every Miner by one tick.
##
## A Miner's input is the ground it stands on: it produces only while its footprint
## covers a Node whose Resource its Recipe produces, and otherwise sits idle without
## accumulating progress — so a Miner placed on bare rock is visibly doing nothing
## rather than invisibly banking time against a Node it might get later.
##
## Nothing is subtracted from the Node. Nodes are inexhaustible (DESIGN.md), which is
## why there is no quantity here to take.
##
## Walks Machines in index order, which is construction order and therefore the same
## on every client.
func _extract() -> void:
	for index: int in range(query_machine_count()):
		if _machine_built_tick[index] == _tick:
			continue

		var definition: MachineDefinition = _definitions.machine(_machine_id[index])
		if definition == null or not definition.is_miner():
			continue

		var recipe: RecipeDefinition = _definitions.recipe_at(definition.recipe_index)
		if recipe == null:
			continue

		var node_index: int = _node_under_machine(index, definition)
		if node_index == -1:
			continue
		if not _recipe_yields(recipe, _node_resource[node_index]):
			continue

		var required: int = _ticks_per_craft(recipe)
		_machine_progress_ticks[index] += 1
		while _machine_progress_ticks[index] >= required:
			_machine_progress_ticks[index] -= required
			_deposit_outputs(index, recipe)


# ── Crafting ──────────────────────────────────────────────────────────────────

## Advances every crafting Machine by one tick.
##
## A crafter's inputs arrive on a Belt, so unlike a Miner it can be starved. A starved
## Machine banks nothing: it does not accumulate a part-craft while it waits for the
## second half of its Recipe, because a Machine that did would pay out the instant its
## inputs landed and a line's first output would appear earlier than the line can
## actually support.
##
## Inputs are consumed when the craft completes rather than when it starts. Either rule
## is defensible; this one keeps "what the Machine is holding" equal to "what a player
## would get back if they knocked it down", and it means a Recipe's duration is the only
## thing between an input arriving and an output appearing.
##
## Walks Machines in index order, which is construction order and therefore the same on
## every client. Index order is safe here in a way it is not for Belts: a Machine's tick
## reads and writes only its own buffers, so no Machine can observe another's progress
## within a tick.
func _craft() -> void:
	for index: int in range(query_machine_count()):
		if _machine_built_tick[index] == _tick:
			continue

		var definition: MachineDefinition = _definitions.machine(_machine_id[index])
		if definition == null or definition.is_miner():
			continue

		var recipe: RecipeDefinition = _definitions.recipe_at(definition.recipe_index)
		if recipe == null or not _holds_a_whole_recipe(index, recipe):
			continue

		var required: int = _ticks_per_craft(recipe)
		_machine_progress_ticks[index] += 1
		while _machine_progress_ticks[index] >= required:
			_machine_progress_ticks[index] -= required
			_consume_inputs(index, recipe)
			_deposit_outputs(index, recipe)
			if not _holds_a_whole_recipe(index, recipe):
				break


## Whether a Machine is holding every input its Recipe needs, in the quantity it needs.
## A Recipe with no inputs is always satisfied — that is a Miner's Recipe, and the
## ground is its input.
func _holds_a_whole_recipe(index: int, recipe: RecipeDefinition) -> bool:
	for slot: int in range(recipe.input_count()):
		var item_id: String = _definitions.item_id(recipe.input_item(slot))
		if item_id.is_empty():
			return false
		if query_machine_input(index, item_id) < recipe.input_quantity(slot):
			return false
	return true


## Takes one craft's inputs out of a Machine's input buffer.
func _consume_inputs(index: int, recipe: RecipeDefinition) -> void:
	for slot: int in range(recipe.input_count()):
		var item_id: String = _definitions.item_id(recipe.input_item(slot))
		if item_id.is_empty():
			continue
		_take_from_input(index, item_id, recipe.input_quantity(slot))


## How many whole ticks one craft takes. A Recipe states its duration in seconds
## because that is how a human reasons about a rate; a tick is the Simulation's only
## unit of time, so the conversion happens once, here, and floors like every other
## lossy operation. A Recipe faster than one tick still takes one: a craft that took
## no time would produce infinitely.
func _ticks_per_craft(recipe: RecipeDefinition) -> int:
	var exact: int = Fixed.mul(recipe.duration_seconds, Fixed.from_int(TICKS_PER_SECOND))
	return maxi(Fixed.floor_to_int(exact), 1)


## The Node a Machine's footprint covers, or -1. A footprint covering two Nodes takes
## the lowest-indexed one, which is the canonical order `MapLayout` sorted them into.
func _node_under_machine(index: int, definition: MachineDefinition) -> int:
	var origin: Vector3i = query_machine_tile(index)
	for node_index: int in range(query_node_count()):
		if WorldGrid.footprint_covers(
			origin, definition.footprint_x, definition.footprint_z, query_node_tile(node_index)
		):
			return node_index
	return -1


## Whether a Recipe produces a given Item id.
func _recipe_yields(recipe: RecipeDefinition, item_id: String) -> bool:
	for slot: int in range(recipe.output_count()):
		if _definitions.item_id(recipe.output_item(slot)) == item_id:
			return true
	return false


## Adds one craft's outputs to a Machine's own output buffer, which is what a Belt running
## out of its port drains. Deliberately uncapped: capping it would stop a Node proving
## itself inexhaustible, and the back-pressure this milestone is about is the Belt filling
## against a full *input* port, which is capped.
func _deposit_outputs(index: int, recipe: RecipeDefinition) -> void:
	for slot: int in range(recipe.output_count()):
		var item_id: String = _definitions.item_id(recipe.output_item(slot))
		if item_id.is_empty():
			continue
		_add_to_buffer(index, item_id, recipe.output_quantity(slot))


## Adds to a Machine's buffer, keeping the Item ids sorted so the buffer's order is a
## property of the content rather than of the order things were produced in.
func _add_to_buffer(index: int, item_id: String, quantity: int) -> void:
	var items: PackedStringArray = _machine_buffer_items[index]
	var counts: PackedInt64Array = _machine_buffer_counts[index]

	var slot: int = items.find(item_id)
	if slot != -1:
		counts[slot] += quantity
		return

	var insert_at: int = items.size()
	for existing: int in range(items.size()):
		if item_id < items[existing]:
			insert_at = existing
			break
	items.insert(insert_at, item_id)
	counts.insert(insert_at, quantity)
	_machine_buffer_items[index] = items
	_machine_buffer_counts[index] = counts


## Takes Items back out of a Machine's output buffer, which is what a Belt loading from
## its port does. An Item id that runs to zero is removed rather than left at zero: a
## buffer listing an Item it does not have would make a Machine look like it is holding
## something it is not.
func _take_from_output(index: int, item_id: String, quantity: int) -> void:
	var items: PackedStringArray = _machine_buffer_items[index]
	var counts: PackedInt64Array = _machine_buffer_counts[index]

	var slot: int = items.find(item_id)
	if slot == -1:
		return
	counts[slot] -= quantity
	if counts[slot] <= 0:
		items.remove_at(slot)
		counts.remove_at(slot)
	_machine_buffer_items[index] = items
	_machine_buffer_counts[index] = counts


# ── Machine input ports ───────────────────────────────────────────────────────

## Puts one Item into a Machine's input buffer, reporting whether it fitted.
##
## This is the back-pressure boundary. A refusal here is what stops a Belt handing over,
## which is what makes the Belt fill up, which is what the player sees. So every reason
## to refuse is a reason the Factory is visibly backed up: a Machine that does not run
## the Item's Recipe, a Miner (whose input is the ground under it, not a port), and a
## buffer already at capacity.
func _accept_input(index: int, item_id: String) -> bool:
	if not _input_has_room(index, item_id):
		return false
	_add_to_input(index, item_id, 1)
	return true


## Whether a Machine's input port would take one more of an Item. The pure half of
## `_accept_input`, so that a query can ask the same question a hand-off asks without
## moving anything.
func _input_has_room(index: int, item_id: String) -> bool:
	var capacity: int = _input_capacity(index, item_id)
	if capacity <= 0:
		return false
	return query_machine_input(index, item_id) < capacity


## How much of an Item a Machine will hold for its Recipe, and 0 for an Item its Recipe
## has no use for. A capacity in crafts rather than in Items, so a Recipe that eats two
## ore a craft buffers twice what one eating a single ore does without anyone tuning the
## two separately.
func _input_capacity(index: int, item_id: String) -> int:
	if not _is_machine(index):
		return 0
	var definition: MachineDefinition = _definitions.machine(_machine_id[index])
	if definition == null or definition.is_miner():
		return 0
	var recipe: RecipeDefinition = _definitions.recipe_at(definition.recipe_index)
	if recipe == null:
		return 0
	for slot: int in range(recipe.input_count()):
		if _definitions.item_id(recipe.input_item(slot)) == item_id:
			return recipe.input_quantity(slot) * maxi(_definitions.machine_input_buffer_crafts, 1)
	return 0


## Adds to a Machine's input buffer, sorted by Item id for the same reason the output
## buffer is.
func _add_to_input(index: int, item_id: String, quantity: int) -> void:
	var items: PackedStringArray = _machine_input_items[index]
	var counts: PackedInt64Array = _machine_input_counts[index]

	var slot: int = items.find(item_id)
	if slot != -1:
		counts[slot] += quantity
		_machine_input_counts[index] = counts
		return

	var insert_at: int = items.size()
	for existing: int in range(items.size()):
		if item_id < items[existing]:
			insert_at = existing
			break
	items.insert(insert_at, item_id)
	counts.insert(insert_at, quantity)
	_machine_input_items[index] = items
	_machine_input_counts[index] = counts


## Takes Items out of a Machine's input buffer, dropping an id that runs to zero.
func _take_from_input(index: int, item_id: String, quantity: int) -> void:
	var items: PackedStringArray = _machine_input_items[index]
	var counts: PackedInt64Array = _machine_input_counts[index]

	var slot: int = items.find(item_id)
	if slot == -1:
		return
	counts[slot] -= quantity
	if counts[slot] <= 0:
		items.remove_at(slot)
		counts.remove_at(slot)
	_machine_input_items[index] = items
	_machine_input_counts[index] = counts


## Places a Machine, or refuses to.
##
## Refused when the action names no Machine, when any tile of the footprint is
## unbuildable — off the Map, or off layer 0 while building is flat — or when the
## footprint overlaps a Machine that is already there. A refusal is a no-op: nothing
## is placed, nothing is logged at error level, and the hash does not move, because a
## misaimed Build Gun is an ordinary thing for a player to do.
##
## The footprint comes from `content/machines.csv` and from nowhere else. There is
## deliberately no second copy of those numbers in this file.
func _apply_build_machine(action: InputAction) -> void:
	var definition: MachineDefinition = _definitions.machine_at(action.build_machine_index())
	if definition == null:
		return

	var tile: Vector3i = action.build_tile()
	if not WorldGrid.footprint_is_buildable(tile, definition.footprint_x, definition.footprint_z):
		return
	if _footprint_is_occupied(tile, definition.footprint_x, definition.footprint_z):
		return

	_machine_id.append(definition.id)
	_machine_tile_x.append(tile.x)
	_machine_tile_y.append(tile.y)
	_machine_tile_z.append(tile.z)
	_machine_built_tick.append(_tick)
	_machine_progress_ticks.append(0)
	_machine_buffer_items.append(PackedStringArray())
	_machine_buffer_counts.append(PackedInt64Array())
	_machine_input_items.append(PackedStringArray())
	_machine_input_counts.append(PackedInt64Array())


## Whether a footprint would overlap something already placed — a Machine or a Belt.
## Walks both in index order, which is cheap at Milestone 1 scale and ordered by
## construction.
func _footprint_is_occupied(origin: Vector3i, size_x: int, size_z: int) -> bool:
	for index: int in range(query_machine_count()):
		var definition: MachineDefinition = _definitions.machine(_machine_id[index])
		if definition == null:
			continue
		if WorldGrid.footprints_overlap(
			origin, size_x, size_z,
			query_machine_tile(index), definition.footprint_x, definition.footprint_z
		):
			return true
	for offset_x: int in range(size_x):
		for offset_z: int in range(size_z):
			var tile: Vector3i = Vector3i(origin.x + offset_x, origin.y, origin.z + offset_z)
			if query_belt_at_tile(tile) != -1:
				return true
	return false


# ── Laying a Belt ─────────────────────────────────────────────────────────────

## Lays a Belt along a straight run, or refuses to.
##
## Refused when the run is not axis-aligned on one layer, when any tile of it cannot
## be built on, or when any tile of it is already taken by a Machine or another Belt.
## Like a refused build, a refused Belt is a silent no-op that does not move the hash:
## dragging a Belt into a wall is an ordinary thing for a player to do.
##
## The run is stored as an anchor, a direction and a length rather than as a list of
## tiles, because that is three integers instead of a growing array and the tiles are
## recoverable from it exactly.
func _apply_build_belt(action: InputAction) -> void:
	var from_tile: Vector3i = action.belt_from_tile()
	var to_tile: Vector3i = action.belt_to_tile()

	var direction: int = WorldGrid.direction_from_to(from_tile, to_tile)
	if direction == -1:
		return

	var tiles: int = WorldGrid.tiles_between(from_tile, to_tile)
	var step: Vector3i = WorldGrid.direction_step(direction)
	for offset: int in range(tiles):
		var tile: Vector3i = from_tile + step * offset
		if not WorldGrid.is_buildable(tile):
			return
		if query_belt_at_tile(tile) != -1 or query_machine_at_tile(tile) != -1:
			return

	_belt_tile_x.append(from_tile.x)
	_belt_tile_y.append(from_tile.y)
	_belt_tile_z.append(from_tile.z)
	_belt_direction.append(direction)
	_belt_tiles.append(tiles)
	_belt_item_ids.append(PackedStringArray())
	_belt_item_offsets.append(PackedInt64Array())
	_belt_update_order_stale = true


## Swaps in a new definition set, or refuses to.
##
## Three ways an attempt is refused, all of them silent in effect and loud in the
## log, because this arrives while a Run is in progress and a Run in progress must
## not be taken down by a typo:
##
##   * no payload — nothing to apply;
##   * the payload failed to load — applying it would leave the Run with no content;
##   * the payload does not hash to the digest the action claims — in lockstep that
##     means the action and the set disagree, and applying it would desync.
##
## A refusal leaves the definitions and the generation counter exactly as they were,
## so a refused reload is not a reload and the hash does not move.
func _apply_reload_definitions(action: InputAction) -> void:
	var incoming: Definitions = action.reload_payload()

	if incoming == null:
		push_error("a definition reload carried no definitions; keeping the current set")
		return
	if incoming.has_errors():
		push_error(
			"a definition reload failed to load; keeping the current set:\n%s"
			% incoming.describe_errors()
		)
		return
	if incoming.digest() != action.declared_digest():
		push_error(
			"a definition reload claimed digest %d but carries %d; keeping the current set"
			% [action.declared_digest(), incoming.digest()]
		)
		return

	_definitions = incoming
	_definition_generation += 1


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
	# The definitions are state. A Run using different content is in a different
	# state even before its first tick, and a Run that reloaded mid-flight is in a
	# different state from one that did not.
	hasher.feed_int(_definitions.digest())
	hasher.feed_int(_definition_generation)
	# The Map. Constant through a Run today, hashed anyway: two Runs on different
	# geography are in different states before either of them steps.
	hasher.feed_ints(_node_tile_x)
	hasher.feed_ints(_node_tile_y)
	hasher.feed_ints(_node_tile_z)
	hasher.feed_ints(_node_depth)
	for resource_id: String in _node_resource:
		hasher.feed_text(resource_id)
	# The Factory: what is built, where, how far through a craft it is, and what it
	# is holding. All of it, because a divergence the harness cannot see is a
	# divergence that reaches co-op.
	hasher.feed_ints(_machine_tile_x)
	hasher.feed_ints(_machine_tile_y)
	hasher.feed_ints(_machine_tile_z)
	hasher.feed_ints(_machine_built_tick)
	hasher.feed_ints(_machine_progress_ticks)
	for index: int in range(query_machine_count()):
		hasher.feed_text(_machine_id[index])
		var items: PackedStringArray = _machine_buffer_items[index]
		var counts: PackedInt64Array = _machine_buffer_counts[index]
		hasher.feed_int(items.size())
		for slot: int in range(items.size()):
			hasher.feed_text(items[slot])
			hasher.feed_int(counts[slot])
		# And what it is holding *for* its Recipe. Hashed separately from the output
		# buffer, because a Machine with two ore waiting and a Machine with two ore made
		# are in different states.
		var input_items: PackedStringArray = _machine_input_items[index]
		var input_counts: PackedInt64Array = _machine_input_counts[index]
		hasher.feed_int(input_items.size())
		for slot: int in range(input_items.size()):
			hasher.feed_text(input_items[slot])
			hasher.feed_int(input_counts[slot])
	# The Belts, and every Item riding one. Items are derived state — recomputed
	# identically on every client and never replicated (ADR 0002) — and that is exactly
	# why they have to be hashed: the guarantee that they are identical everywhere is
	# worth nothing if nothing checks it.
	hasher.feed_ints(_belt_tile_x)
	hasher.feed_ints(_belt_tile_y)
	hasher.feed_ints(_belt_tile_z)
	hasher.feed_ints(_belt_direction)
	hasher.feed_ints(_belt_tiles)
	for index: int in range(query_belt_count()):
		var belt_items: PackedStringArray = _belt_item_ids[index]
		var belt_offsets: PackedInt64Array = _belt_item_offsets[index]
		hasher.feed_int(belt_items.size())
		for slot: int in range(belt_items.size()):
			hasher.feed_text(belt_items[slot])
			hasher.feed_int(belt_offsets[slot])
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


## The content definitions this Run is using.
##
## Handed out by reference rather than copied, which is the one exception to the
## copy-out rule and is safe for the reason the rule exists: a loaded definition set
## is immutable, so there is nothing a caller could mutate. A reload replaces it.
func query_definitions() -> Definitions:
	return _definitions


## Whether the definitions loaded cleanly. False means the Run must not start.
func query_definitions_loaded() -> bool:
	return not _definitions.has_errors()


## Why the definitions did not load, each naming the file and the row. Empty when
## they did.
func query_definition_errors() -> PackedStringArray:
	return _definitions.errors.duplicate()


## The digest of the definition set in use. What a recording stores so a replay
## cannot quietly run against different content.
func query_definition_digest() -> int:
	return _definitions.digest()


## How many reloads this Run has applied. 0 for a Run that has not hot-reloaded.
func query_definition_generation() -> int:
	return _definition_generation


## How many Nodes the Map holds.
func query_node_count() -> int:
	return _node_resource.size()


## The tile a Node sits on. An unknown index reads as the origin rather than
## crashing, for the same reason an unknown player does.
func query_node_tile(index: int) -> Vector3i:
	if not _is_node(index):
		return Vector3i.ZERO
	return Vector3i(_node_tile_x[index], _node_tile_y[index], _node_tile_z[index])


## The Resource a Node yields, as an Item id. "" for an unknown Node — never a
## plausible-looking default, because a mistyped index must not read as iron ore.
func query_node_resource(index: int) -> String:
	if not _is_node(index):
		return ""
	return _node_resource[index]


## The Depth tier a Node sits at. Tiers start at 1; 0 for an unknown Node.
func query_node_depth(index: int) -> int:
	if not _is_node(index):
		return 0
	return _node_depth[index]


## The Node on a tile, or -1. Nodes occupy one tile each.
func query_node_at_tile(tile: Vector3i) -> int:
	for index: int in range(query_node_count()):
		if query_node_tile(index) == tile:
			return index
	return -1


## How many Machines are standing.
func query_machine_count() -> int:
	return _machine_id.size()


## The definition id of a Machine, as written in `content/machines.csv`. "" for an
## unknown index.
func query_machine_id(index: int) -> String:
	if not _is_machine(index):
		return ""
	return _machine_id[index]


## The tile a Machine's footprint is anchored at.
func query_machine_tile(index: int) -> Vector3i:
	if not _is_machine(index):
		return Vector3i.ZERO
	return Vector3i(_machine_tile_x[index], _machine_tile_y[index], _machine_tile_z[index])


## The Machine whose footprint covers a tile, or -1. The footprint is whatever
## `content/machines.csv` states, so this answers for every tile a 4x4 Machine sits
## on, not only its anchor.
func query_machine_at_tile(tile: Vector3i) -> int:
	for index: int in range(query_machine_count()):
		var definition: MachineDefinition = _definitions.machine(_machine_id[index])
		if definition == null:
			continue
		if WorldGrid.footprint_covers(
			query_machine_tile(index), definition.footprint_x, definition.footprint_z, tile
		):
			return index
	return -1


## How much of an Item a Machine is holding in its own output buffer. 0 for an Item
## it has never produced, and for an unknown Machine.
func query_machine_output(index: int, item_id: String) -> int:
	if not _is_machine(index):
		return 0
	var items: PackedStringArray = _machine_buffer_items[index]
	var slot: int = items.find(item_id)
	if slot == -1:
		return 0
	var counts: PackedInt64Array = _machine_buffer_counts[index]
	return counts[slot]


## The Item ids a Machine is holding, sorted. A copy, like every query.
func query_machine_output_items(index: int) -> PackedStringArray:
	if not _is_machine(index):
		return PackedStringArray()
	var items: PackedStringArray = _machine_buffer_items[index]
	return items.duplicate()


## How many Items of all kinds a Machine is holding.
func query_machine_output_total(index: int) -> int:
	if not _is_machine(index):
		return 0
	var total: int = 0
	for count: int in _machine_buffer_counts[index]:
		total += count
	return total


## How much of an Item a Machine is holding for its Recipe, in its input buffer. 0 for
## an Item its Recipe has no use for, and for an unknown Machine.
func query_machine_input(index: int, item_id: String) -> int:
	if not _is_machine(index):
		return 0
	var items: PackedStringArray = _machine_input_items[index]
	var slot: int = items.find(item_id)
	if slot == -1:
		return 0
	var counts: PackedInt64Array = _machine_input_counts[index]
	return counts[slot]


## The Item ids a Machine is holding for its Recipe, sorted.
func query_machine_input_items(index: int) -> PackedStringArray:
	if not _is_machine(index):
		return PackedStringArray()
	var items: PackedStringArray = _machine_input_items[index]
	return items.duplicate()


## How many Items of all kinds a Machine is holding for its Recipe.
func query_machine_input_total(index: int) -> int:
	if not _is_machine(index):
		return 0
	var total: int = 0
	for count: int in _machine_input_counts[index]:
		total += count
	return total


## How much of an Item a Machine will hold for its Recipe before its input port refuses
## more. 0 for an Item its Recipe does not use — which is how a Belt pointed at the
## wrong Machine backs up instead of quietly voiding what it carries.
func query_machine_input_capacity(index: int, item_id: String) -> int:
	return _input_capacity(index, item_id)


## How much of an Item the whole Factory is holding — in output buffers, in input
## buffers, and riding on Belts. What a HUD shows, and it counts the Belts because ore
## in transit has not vanished.
func query_item_total(item_id: String) -> int:
	var total: int = 0
	for index: int in range(query_machine_count()):
		total += query_machine_output(index, item_id)
		total += query_machine_input(index, item_id)
	for index: int in range(query_belt_count()):
		var items: PackedStringArray = _belt_item_ids[index]
		for slot: int in range(items.size()):
			if items[slot] == item_id:
				total += 1
	return total


## Whether a Machine cannot run for want of its inputs.
##
## The one question a player asks of a Machine that is doing nothing, answered by the
## Simulation rather than inferred by the renderer from a count that stopped moving. A
## Miner is starved when the ground under it holds no Node its Recipe can take; a crafter
## is starved when its input buffer does not hold a whole Recipe's worth.
##
## False for a Machine with no definition or no Recipe: that is a broken definition set,
## which `query_definitions_loaded` reports, not a starved Machine.
func query_machine_is_starved(index: int) -> bool:
	if not _is_machine(index):
		return false
	var definition: MachineDefinition = _definitions.machine(_machine_id[index])
	if definition == null:
		return false
	var recipe: RecipeDefinition = _definitions.recipe_at(definition.recipe_index)
	if recipe == null:
		return false

	if definition.is_miner():
		var under: int = _node_under_machine(index, definition)
		if under == -1:
			return true
		return not _recipe_yields(recipe, _node_resource[under])

	return not _holds_a_whole_recipe(index, recipe)


## The Node a Machine's footprint covers, or -1. A Miner over no Node produces
## nothing, and this is how the rendering layer can say so.
func query_node_under_machine(index: int) -> int:
	if not _is_machine(index):
		return -1
	var definition: MachineDefinition = _definitions.machine(_machine_id[index])
	if definition == null:
		return -1
	return _node_under_machine(index, definition)


## How many Belts are laid.
func query_belt_count() -> int:
	return _belt_tiles.size()


## How many tiles long a Belt's run is. 0 for an unknown Belt.
func query_belt_length_tiles(index: int) -> int:
	if not _is_belt(index):
		return 0
	return _belt_tiles[index]


## Which way a Belt carries, as a `WorldGrid` direction. -1 for an unknown Belt.
func query_belt_direction(index: int) -> int:
	if not _is_belt(index):
		return -1
	return _belt_direction[index]


## The nth tile of a Belt's run, counted from the end Items enter at. The origin for
## an unknown Belt or an out-of-range step, for the same reason an unknown Machine
## reads as the origin rather than crashing.
func query_belt_tile(index: int, step: int) -> Vector3i:
	if not _is_belt(index):
		return Vector3i.ZERO
	if step < 0 or step >= _belt_tiles[index]:
		return Vector3i.ZERO
	return _belt_entry_tile(index) + WorldGrid.direction_step(_belt_direction[index]) * step


## The Belt covering a tile, or -1. A Belt is one tile wide, so this answers for every
## tile of a run and not only its anchor.
func query_belt_at_tile(tile: Vector3i) -> int:
	for index: int in range(query_belt_count()):
		if _belt_covers(index, tile):
			return index
	return -1


## How many Items a Belt is carrying.
func query_belt_item_count(index: int) -> int:
	if not _is_belt(index):
		return 0
	var offsets: PackedInt64Array = _belt_item_offsets[index]
	return offsets.size()


## The Item in one of a Belt's slots, counted from the far end — slot 0 is the Item
## nearest the end it will leave by. "" for an unknown Belt or slot, never a
## plausible-looking default.
func query_belt_item_id(index: int, slot: int) -> String:
	if not _is_belt(index):
		return ""
	var items: PackedStringArray = _belt_item_ids[index]
	if slot < 0 or slot >= items.size():
		return ""
	return items[slot]


## Where an Item on a Belt actually is, in fixed-point metres on the horizontal plane.
##
## The truth rather than an approximation, and the reason the Godot layer needs no
## notion of Belt motion of its own: a backed-up Belt reads as a queue of Items packed
## at their spacing because that is literally where they are.
func query_belt_item_position_metres(index: int, slot: int) -> FixedVec2:
	if not _is_belt(index):
		return FixedVec2.zero()
	var offsets: PackedInt64Array = _belt_item_offsets[index]
	if slot < 0 or slot >= offsets.size():
		return FixedVec2.zero()

	var step: Vector3i = WorldGrid.direction_step(_belt_direction[index])
	var entry: FixedVec2 = WorldGrid.tile_centre_metres(_belt_entry_tile(index))
	var half_tile: int = Fixed.from_rational(WorldGrid.TILE_SIZE_METRES, 2)
	# An Item's centre is half a spacing past its own position along the run, measured
	# from the entry *edge* of the first tile rather than from that tile's centre.
	var along: int = _subunits_to_metres(2 * offsets[slot] + _belt_spacing_subunits())
	var from_edge: int = along - half_tile
	return FixedVec2.new(entry.x + step.x * from_edge, entry.z + step.z * from_edge)


## How far along a Belt an Item has travelled, in fixed-point metres from the end it
## entered by. What a test or a diagnostic reads to say where a queue begins.
func query_belt_item_distance_metres(index: int, slot: int) -> int:
	if not _is_belt(index):
		return 0
	var offsets: PackedInt64Array = _belt_item_offsets[index]
	if slot < 0 or slot >= offsets.size():
		return 0
	return _subunits_to_metres(2 * offsets[slot] + _belt_spacing_subunits())


## How many Items a Belt holds when it is completely full: its length times the density
## tuning states.
func query_belt_capacity(index: int) -> int:
	if not _is_belt(index):
		return 0
	return _belt_tiles[index] * _belt_items_per_tile()


## Whether a Belt is backed up: its leading Item has reached the far end and whatever is
## there will not take it.
##
## The diagnosis a player makes by looking at the Factory, available to the HUD and to a
## test as one boolean. True from the first Item that cannot get off, not only once the
## whole run is packed — a Belt one Item short of full is already losing throughput.
func query_belt_is_stalled(index: int) -> bool:
	if not _is_belt(index):
		return false
	return _hand_off_blocked(index)


## Whether a Belt is carrying as many Items as it can hold.
func query_belt_is_full(index: int) -> bool:
	if not _is_belt(index):
		return false
	return query_belt_item_count(index) >= query_belt_capacity(index)


## How many ticks pass between consecutive Items on a saturated Belt. The Belt's rating
## from `content/tuning.toml`, turned into the whole number of ticks the Simulation
## actually works in.
func query_belt_ticks_per_item() -> int:
	return _belt_ticks_per_item()


## How many Items fit on one tile of Belt.
func query_belt_items_per_tile() -> int:
	return _belt_items_per_tile()


## The grid's tile edge length in fixed-point metres. 2 m, per DESIGN.md.
func query_tile_size_metres() -> int:
	return WorldGrid.tile_size_metres()


## How far the Map extends from the origin in tiles, on both horizontal axes.
func query_grid_half_extent_tiles() -> int:
	return WorldGrid.HALF_EXTENT_TILES


## Whether something may be built on a tile: inside the Map, and on a layer the
## build rules allow. Only layer 0 while building is flat.
func query_is_buildable_tile(tile: Vector3i) -> bool:
	return WorldGrid.is_buildable(tile)


## The centre of a tile on the horizontal plane, in fixed-point metres. What the
## rendering layer places a Machine's mesh at.
func query_tile_centre_metres(tile: Vector3i) -> FixedVec2:
	return WorldGrid.tile_centre_metres(tile)


## The floor height of a layer in fixed-point metres. 0 for the ground; a 4 m storey
## is reserved above it for when vertical building is switched on.
func query_layer_height_metres(layer: int) -> int:
	return WorldGrid.layer_height_metres(layer)


## The tile a Belt's run is anchored at — the end Items enter from.
func _belt_entry_tile(index: int) -> Vector3i:
	return Vector3i(_belt_tile_x[index], _belt_tile_y[index], _belt_tile_z[index])


## Whether a Belt's run covers a tile.
func _belt_covers(index: int, tile: Vector3i) -> bool:
	var entry: Vector3i = _belt_entry_tile(index)
	if tile.y != entry.y:
		return false
	var step: Vector3i = WorldGrid.direction_step(_belt_direction[index])
	var along: int = (tile.x - entry.x) * step.x + (tile.z - entry.z) * step.z
	if along < 0 or along >= _belt_tiles[index]:
		return false
	return entry + step * along == tile


func _is_belt(index: int) -> bool:
	return index >= 0 and index < _belt_tiles.size()


func _is_machine(index: int) -> bool:
	return index >= 0 and index < _machine_id.size()


func _is_node(index: int) -> bool:
	return index >= 0 and index < _node_resource.size()


func _is_player(player_id: int) -> bool:
	return player_id >= 0 and player_id < _player_x.size()
