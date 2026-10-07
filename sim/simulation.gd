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
## This is the Miner's own output buffer. Belts drain it in the next ticket; until
## then it only fills, which is exactly what makes extraction observable.
var _machine_buffer_items: Array = []
var _machine_buffer_counts: Array = []


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

	_extract()

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


## Adds one craft's outputs to a Machine's own buffer. No capacity yet — the Belt
## ticket is what gives a buffer somewhere to drain to, and a cap before then would
## stop extraction being observable.
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


## Whether a footprint would overlap one already placed. Walks the Machines in index
## order, which is cheap at Milestone 1 scale and ordered by construction.
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
	return false


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


## How much of an Item the whole Factory is holding. What a HUD shows.
func query_item_total(item_id: String) -> int:
	var total: int = 0
	for index: int in range(query_machine_count()):
		total += query_machine_output(index, item_id)
	return total


## The Node a Machine's footprint covers, or -1. A Miner over no Node produces
## nothing, and this is how the rendering layer can say so.
func query_node_under_machine(index: int) -> int:
	if not _is_machine(index):
		return -1
	var definition: MachineDefinition = _definitions.machine(_machine_id[index])
	if definition == null:
		return -1
	return _node_under_machine(index, definition)


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


func _is_machine(index: int) -> bool:
	return index >= 0 and index < _machine_id.size()


func _is_node(index: int) -> bool:
	return index >= 0 and index < _node_resource.size()


func _is_player(player_id: int) -> bool:
	return player_id >= 0 and player_id < _player_x.size()
