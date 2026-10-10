## The shape of the Factory a player has to build, read out of the definition set.
##
## **#53, and the complaint it came from was "please simplify the hotbar right now so I am
## CRYSTAL clear about what chain of buildings to build".** The picker #36 built is one cell
## per Machine in sorted id order, which puts the Ammo Press first and the Miner fourth — a
## player reading left to right was being shown the chain backwards. Nothing was wrong with
## the cells; what was missing was the *order*, and the order was never anywhere to be read.
##
## It lives in `game/` for the reason `Objective` and `BuildGun.refusal_text` do: a Recipe's
## inputs are a fact and "this is what you build after that" is a sentence about them. The
## Simulation does not know this file exists, nothing here is state, and asking any of it
## leaves the state hash exactly where it was.
##
## **The order is derived and never typed.** This project's central rule is that adding a
## Machine is a row — there is no registry, no enum, and the set of Items is exactly what the
## Recipes mention. A hand-written hotbar order would be a second content table living in
## GDScript, and it would go stale the first time somebody added a Machine. So the chain is
## read off the one place it actually exists: a Machine's Recipe names what it eats and what
## it makes, `Definitions` interns both, and "what feeds what" is therefore a question the
## definition set can answer.
##
## Three derived quantities, and the whole of the file is them:
##
## - **A stage** is how many crafts deep a Machine sits. A Machine with no inputs is stage 0
##   — a Miner's input is the ground — and anything else is one past the deepest Item it
##   eats. So ore is stage 0, the Smelter that eats it is stage 1, the Ammo Press that eats
##   the Smelter's plate is 2, and the Turret that spends its rounds is 3. That is the
##   `column` a cell is drawn in, and it is the sense in which column N feeds column N+1:
##   every Machine in a column eats something made in the one before it, by construction.
## - **A reach** is how far downstream of a Machine the chain goes, following output Item to
##   consuming Machine. The Miner's ore reaches the Turret, three stages on; the Coal Miner's
##   coal reaches the Boiler and stops. That is what sorts a column, and it is what puts the
##   **main line along the top row** and the branches underneath it — derived, rather than
##   somebody deciding which branch is the important one.
## - **Whether a Delivery tier gates it**, through `Definitions.locks_machine`, which is the
##   same authority the picker's lock tint already reads. A gated Machine sorts after an
##   ungated one in its column, so the deeper Miners sit below the Miner a Run opens with.
##
## **The lock is read as content and not as Run state, deliberately.** `locks_machine` asks
## whether *any* tier names a Machine, which is a property of `content/deliveries.csv` and
## fixed for a definition set — not whether *this* Run has earned it, which changes mid-Run.
## An order that moved when a Delivery landed would renumber the keys under a player who had
## just learnt them, and a key that moves is worse than a key in an odd place. What a Run has
## earned is still drawn, by the tint, every frame.
class_name BuildChain
extends RefCounted


## The Machines, in the order a player should read them: row by row, left to right.
##
## **Row-major over a column-major grid**, which is the one arrangement that gets both halves
## right. The grid is stages across and branches down, so the chain reads left to right along
## the top. The *keys* then run along that top row first — 1, 2, 3, 4 is the line a player
## has to build, in the order they build it — rather than down the first column, which would
## hand the chain the keys 1, 5, 7, 9 and ask a player to learn a lookup table.
##
## So this array is both the key order and the reading order, and `column_of` / `row_of` say
## where each entry is drawn. One authority for all three.
static func order(definitions: Definitions) -> PackedInt64Array:
	return _layout(definitions).order


## Which column a Machine's cell is drawn in: its stage, counted in crafts from the ground.
## Parallel to `order`.
static func column_of(definitions: Definitions) -> PackedInt64Array:
	return _layout(definitions).columns


## Which row within its column a Machine's cell is drawn on. Parallel to `order`. Row 0 is
## the main line, because that is what the longest reach downstream means.
static func row_of(definitions: Definitions) -> PackedInt64Array:
	return _layout(definitions).rows


## Where a Machine's own definition index sits in `order`, or -1 for one that is not there.
##
## The inverse, because everything that *acts* on a Machine — a `SELECT_MACHINE` intent, the
## Simulation's own `query_player_selected_machine_index` — travels as a definition index,
## and only the drawing and the keys travel as a cell.
static func cell_of(definitions: Definitions, machine_index: int) -> int:
	var order_: PackedInt64Array = order(definitions)
	for cell: int in range(order_.size()):
		if order_[cell] == machine_index:
			return cell
	return -1


## The first Machine in chain order that fills a Role and that this Run can actually build,
## or -1 when there is none.
##
## This is what lets the hotbar mark the cell the objective line is talking about: the line
## says "place a Miner" and this says *which* cell that is, off the same content. It asks the
## Simulation about the lock because that half genuinely is Run state — a player must not be
## pointed at a Machine a Delivery still has shut.
static func first_unlocked_of_role(sim: Simulation, role: MachineDefinition.Role) -> int:
	var definitions: Definitions = sim.query_definitions()
	for machine_index: int in order(definitions):
		var machine: MachineDefinition = definitions.machine_at(machine_index)
		if machine.role == role and sim.query_machine_is_unlocked(machine_index):
			return machine_index
	return -1


## The first Machine in chain order whose Recipe produces an Item and that this Run can
## actually build, or -1 when there is none.
##
## **`first_unlocked_of_role`'s sibling, and #71 is what it is for.** The objective line's
## last step is about the goods the open Delivery tier is waiting for, and "which cell makes
## coal" is the same category of question as "which cell is the Miner": a fact about the
## content, answered off the chain order so that a Map whose chain opens differently points at
## a different cell and nothing here names a row. The lock is asked of the Simulation for
## `first_unlocked_of_role`'s reason — a player must not be pointed at a cell a Delivery has
## shut.
##
## A Role would not have answered it. Coal and ore are both mined, plate and Ammunition are
## both crafted, and what separates the Machine a player needs from the one beside it is the
## Item it puts out.
static func first_unlocked_producer_of(sim: Simulation, item_index: int) -> int:
	if item_index < 0:
		return -1
	var definitions: Definitions = sim.query_definitions()
	for machine_index: int in order(definitions):
		var machine: MachineDefinition = definitions.machine_at(machine_index)
		if machine == null or not sim.query_machine_is_unlocked(machine_index):
			continue
		var recipe: RecipeDefinition = definitions.recipe_at(machine.recipe_index)
		if recipe != null and _produces(recipe, item_index):
			return machine_index
	return -1


static func _produces(recipe: RecipeDefinition, item: int) -> bool:
	for slot: int in range(recipe.output_count()):
		if recipe.output_item(slot) == item:
			return true
	return false


## Which group a cell is in: the chain itself, or what a Delivery tier gates. Parallel to
## `order`.
static func group_of(definitions: Definitions) -> PackedInt64Array:
	return _layout(definitions).groups


## The Machines a Run opens able to build: the Factory the chain is actually about.
const GROUP_CHAIN: int = 0

## What some tier of `content/deliveries.csv` gates — past the end of the chain, in its own
## columns, so it cannot make the hotbar taller than the chain is.
const GROUP_LATER: int = 1


## What `order`, `column_of`, `row_of` and `group_of` all read, so the four cannot come apart.
class Layout extends RefCounted:
	var order: PackedInt64Array = PackedInt64Array()
	var columns: PackedInt64Array = PackedInt64Array()
	var rows: PackedInt64Array = PackedInt64Array()
	var groups: PackedInt64Array = PackedInt64Array()


## Derives the whole grid. Cheap — the Machine list is ten long and the Item list shorter —
## and called from a picker that rebuilds only when the definition set changes.
##
## **Two groups, and the second one is a render's doing.** Dropping the deeper Miners into
## stage 0 beside the Miner a Run opens with is where the chain says they go, and it makes
## that column four cells tall — and a hotbar is as tall as its tallest column, so two
## Machines nobody can build yet pushed the whole chain four rows up the screen and over the
## Factory it is about. They are *later*, which `content/deliveries.csv` already knows, so
## they go in their own columns past the end of the chain and the grid stays as tall as the
## chain is. That is also #53's third criterion — separate the opening line from everything
## else — arriving as a layout constraint rather than as a preference.
static func _layout(definitions: Definitions) -> Layout:
	var layout: Layout = Layout.new()
	if definitions == null or definitions.has_errors():
		return layout

	var stages: PackedInt64Array = _stages(definitions)
	var reaches: PackedInt64Array = _reaches(definitions, stages)

	var deepest: int = 0
	for stage: int in stages:
		deepest = maxi(deepest, stage)

	# The chain: a column per stage, deepest reach on top. Only what a Run opens able to
	# build, because that is the Factory the arrows are a statement about.
	var chain: Array = []
	for column: int in range(deepest + 1):
		var entries: PackedInt64Array = _column(definitions, stages, reaches, column, false)
		if not entries.is_empty():
			chain.append(entries)
	var tallest: int = 1
	for entries: PackedInt64Array in chain:
		tallest = maxi(tallest, entries.size())

	# What a tier gates, filled column-major into columns no taller than the chain, in stage
	# order and then by the same reach and id the chain is sorted by.
	var gated: PackedInt64Array = PackedInt64Array()
	for column: int in range(deepest + 1):
		gated.append_array(_column(definitions, stages, reaches, column, true))
	var later: Array = []
	for slot: int in range(gated.size()):
		if slot % tallest == 0:
			later.append(PackedInt64Array())
		var column_entries: PackedInt64Array = later[later.size() - 1]
		column_entries.append(gated[slot])
		later[later.size() - 1] = column_entries

	# Row-major within each group, the chain before what is gated — so the keys run 1, 2, 3,
	# 4 along the line a player has to build and reach what is locked afterwards.
	_fill(layout, chain, GROUP_CHAIN, 0, tallest)
	_fill(layout, later, GROUP_LATER, chain.size(), tallest)
	return layout


## Appends one group's cells to the layout, row by row and left to right.
static func _fill(
	layout: Layout, grid: Array, group: int, first_column: int, tallest: int
) -> void:
	for row: int in range(tallest):
		for column: int in range(grid.size()):
			var entries: PackedInt64Array = grid[column]
			if row >= entries.size():
				continue
			layout.order.append(entries[row])
			layout.columns.append(first_column + column)
			layout.rows.append(row)
			layout.groups.append(group)


## The Machines of one stage on one side of the gate, deepest reach first, with ties
## broken by definition index — which is id order, the order `Definitions` interns them in, so
## the grid is a function of the content and never of the order rows happen to be written in.
static func _column(
	definitions: Definitions,
	stages: PackedInt64Array,
	reaches: PackedInt64Array,
	column: int,
	want_gated: bool
) -> PackedInt64Array:
	var keyed: Array = []
	for machine_index: int in range(definitions.machine_count()):
		if stages[machine_index] != column:
			continue
		var id: String = definitions.machine_at(machine_index).id
		if definitions.locks_machine(id) != want_gated:
			continue
		keyed.append([-reaches[machine_index], machine_index])
	keyed.sort()
	var entries: PackedInt64Array = PackedInt64Array()
	for key: Array in keyed:
		entries.append(key[1])
	return entries


## How many crafts deep each Machine sits. 0 for one with no inputs, and otherwise one past
## the deepest Item it eats.
##
## Resolved by sweeping until nothing moves rather than by recursing, because a Recipe table
## is data a designer edits and nothing stops one describing a loop — plate out of ammunition
## out of plate. A sweep bounded by the Machine count terminates on any table at all and
## leaves whatever it could not resolve at 0, where it reads as "buildable from the ground",
## which is the safe thing for a hotbar to say about content nobody can untangle.
static func _stages(definitions: Definitions) -> PackedInt64Array:
	var stages: PackedInt64Array = PackedInt64Array()
	stages.resize(definitions.machine_count())
	# The depth of each Item: the stage of the Machine that makes it. Unmade Items stay 0.
	var item_depth: PackedInt64Array = PackedInt64Array()
	item_depth.resize(definitions.item_count())

	for _sweep: int in range(definitions.machine_count()):
		var moved: bool = false
		for machine_index: int in range(definitions.machine_count()):
			var recipe: RecipeDefinition = definitions.recipe(
				definitions.machine_at(machine_index).recipe_id
			)
			if recipe == null:
				continue
			var stage: int = 0
			for slot: int in range(recipe.input_count()):
				stage = maxi(stage, item_depth[recipe.input_item(slot)] + 1)
			if stage != stages[machine_index]:
				stages[machine_index] = stage
				moved = true
			for slot: int in range(recipe.output_count()):
				var item: int = recipe.output_item(slot)
				if stage > item_depth[item]:
					item_depth[item] = stage
					moved = true
		if not moved:
			break
	return stages


## How far downstream of each Machine the chain goes, in stages: its own stage, or the
## furthest stage anything that eats what it makes reaches. Swept for the same reason the
## stages are.
static func _reaches(definitions: Definitions, stages: PackedInt64Array) -> PackedInt64Array:
	var reaches: PackedInt64Array = stages.duplicate()
	for _sweep: int in range(definitions.machine_count()):
		var moved: bool = false
		for machine_index: int in range(definitions.machine_count()):
			var recipe: RecipeDefinition = definitions.recipe(
				definitions.machine_at(machine_index).recipe_id
			)
			if recipe == null:
				continue
			for slot: int in range(recipe.output_count()):
				var item: int = recipe.output_item(slot)
				for eater: int in range(definitions.machine_count()):
					var eats: RecipeDefinition = definitions.recipe(
						definitions.machine_at(eater).recipe_id
					)
					if eats == null or not _consumes(eats, item):
						continue
					if reaches[eater] > reaches[machine_index]:
						reaches[machine_index] = reaches[eater]
						moved = true
		if not moved:
			break
	return reaches


static func _consumes(recipe: RecipeDefinition, item: int) -> bool:
	for slot: int in range(recipe.input_count()):
		if recipe.input_item(slot) == item:
			return true
	return false


## Which key reaches a cell, as the hotbar prints it on the cell and as the objective line
## names it. Ten of them — `1` to `9` and `0` — which is the whole of the shipped Machine
## list and as many as a hand reaches without looking. Past that a player scrolls, which
## still works and always did.
##
## **It lives here rather than in the renderer because #53 gave it a second reader.** The
## objective line says "key 2" and the cell says "[2]", and a chain that renumbered under one
## of them would be the exact disagreement this file exists to prevent.
static func key_label(cell: int) -> String:
	if cell < 0:
		return ""
	if cell < 9:
		return str(cell + 1)
	if cell == 9:
		return "0"
	return "·"


## The key that reaches a Machine, for the middle of a sentence — "key 2" — or "" for one no
## key reaches. Derived, so a Machine added as a row moves the words with it.
static func key_phrase(definitions: Definitions, machine_index: int) -> String:
	var label: String = key_label(cell_of(definitions, machine_index))
	return "" if label.is_empty() or label == "·" else "key %s" % label
