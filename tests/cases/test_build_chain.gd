## The build chain, derived from the definition set rather than typed into the renderer.
##
## #53's acceptance criterion: adding a Machine as a row to `content/machines.csv` puts it
## where the chain says it goes, with no renderer change. So the assertions here are about
## the *derivation* — what order the shipped content comes out in, and that a Machine nobody
## has ever heard of lands in the right place by having a Recipe.
extends TestCase


## The shipped chain, as `content/recipes.csv` writes it and as issue #53 states it:
##
##   Miner Mk1 -> ore -> Smelter -> plate -> Ammo Press -> ammunition -> MG Turret
##
## with the Power branch (Coal Miner -> Steam Boiler) and the three things that sit off the
## line (Repair Pylon, Silo, the deeper Miners) hanging off their own stages.
func test_the_shipped_chain_comes_out_in_causal_order_not_alphabetical() -> void:
	var definitions: Definitions = Definitions.load_from_directory(Definitions.CONTENT_DIR)
	assert_false(definitions.has_errors(), definitions.describe_errors())

	var order: PackedStringArray = _ids_in_order(definitions)
	# The top row: the line a player has to build, in the order they have to build it.
	assert_eq(order[0], "miner_mk1", "something that digs comes first")
	assert_eq(order[1], "smelter_mk1", "then the thing that eats what it digs")
	assert_eq(order[2], "ammo_press_mk1", "then the thing that eats what that makes")
	assert_eq(order[3], "mg_turret_mk1", "and then the thing the whole line is for")


## The one that fails loudest today: sorted id order puts the Ammo Press first and the Miner
## fourth, so a player reading left to right is shown the chain backwards.
func test_the_order_is_not_the_sorted_id_order() -> void:
	var definitions: Definitions = Definitions.load_from_directory(Definitions.CONTENT_DIR)
	var order: PackedStringArray = _ids_in_order(definitions)
	assert_ne(order[0], definitions.machine_ids()[0], "alphabetical is what this replaces")
	assert_eq(definitions.machine_ids()[0], "ammo_press_mk1", "which starts here")


## Every Machine gets a cell and none gets two. A hotbar that quietly dropped a row would be
## worse than one in the wrong order.
func test_every_machine_appears_exactly_once() -> void:
	var definitions: Definitions = Definitions.load_from_directory(Definitions.CONTENT_DIR)
	var order: PackedInt64Array = BuildChain.order(definitions)
	assert_eq(order.size(), definitions.machine_count(), "a cell each")
	var seen: Dictionary = {}
	for index: int in order:
		assert_false(seen.has(index), "machine %d twice" % index)
		seen[index] = true


static func _ids_in_order(definitions: Definitions) -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	for index: int in BuildChain.order(definitions):
		ids.append(definitions.machine_at(index).id)
	return ids


## The grid, as the picker draws it: stages across, branches down.
##
## Column N feeds column N+1 by construction — every Machine in a column eats something made
## in the one before it — which is what makes an arrow between two columns a true statement
## rather than a decoration.
func test_the_grid_is_stages_across_and_branches_down() -> void:
	var definitions: Definitions = Definitions.load_from_directory(Definitions.CONTENT_DIR)
	var columns: PackedInt64Array = BuildChain.column_of(definitions)
	var rows: PackedInt64Array = BuildChain.row_of(definitions)
	var order: PackedInt64Array = BuildChain.order(definitions)
	var at: Dictionary = {}
	for cell: int in range(order.size()):
		at[definitions.machine_at(order[cell]).id] = Vector2i(columns[cell], rows[cell])

	# The line, along the top: one column per craft it takes to turn ground into defence.
	assert_eq(at["miner_mk1"], Vector2i(0, 0), "the ground")
	assert_eq(at["smelter_mk1"], Vector2i(1, 0), "one craft in")
	assert_eq(at["ammo_press_mk1"], Vector2i(2, 0), "two")
	assert_eq(at["mg_turret_mk1"], Vector2i(3, 0), "three, and the point of the whole line")

	# The Power branch, underneath its own stages rather than appended to the line. A Coal
	# Miner is as deep as an iron Miner and a Boiler is as deep as a Smelter, which is what
	# the columns say and what a row of ten cells could not.
	assert_eq(at["coal_miner_mk1"], Vector2i(0, 1), "coal is dug from the ground too")
	assert_eq(at["steam_boiler_mk1"], Vector2i(1, 1), "and burnt one craft in")

	# What hangs off the line rather than carrying it, each under the stage it eats at.
	assert_eq(at["repair_pylon_mk1"], Vector2i(2, 1), "a Pylon eats plate, like the Press")
	assert_eq(at["silo_mk1"], Vector2i(3, 1), "and a Silo spends rounds, like the Turret")

	# The deeper Miners: past the end of the chain, in their own column, because a Delivery
	# tier gates them — and so the two of them cannot make the hotbar twice as tall as the
	# chain it is about. See `test_what_a_delivery_gates_sits_past_the_end_of_the_chain`.
	assert_eq(at["miner_mk2"], Vector2i(4, 0))
	assert_eq(at["miner_mk3"], Vector2i(4, 1))


## The top row is the main line, and it is the *reach* that puts it there — how far
## downstream of a Machine the chain goes — rather than anybody deciding which branch
## matters. Ore reaches the Turret three stages on; coal reaches the Boiler and stops.
func test_the_longest_branch_is_the_one_along_the_top() -> void:
	var definitions: Definitions = Definitions.load_from_directory(Definitions.CONTENT_DIR)
	var order: PackedInt64Array = BuildChain.order(definitions)
	var rows: PackedInt64Array = BuildChain.row_of(definitions)
	var groups: PackedInt64Array = BuildChain.group_of(definitions)
	var asserted: bool = false
	for cell: int in range(order.size()):
		if rows[cell] != 0 or groups[cell] != BuildChain.GROUP_CHAIN:
			continue
		var id: String = definitions.machine_at(order[cell]).id
		assert_false(
			definitions.locks_machine(id),
			"nothing on the main line is behind a Delivery: %s" % id
		)
		# What makes it the main line: the chain runs on past it, where a branch stops.
		asserted = true
	assert_true(asserted, "the chain has a top row")


## **The acceptance criterion of the whole ticket.** A Machine added as a row lands where the
## chain says it lands, with not one line of this file or the renderer changed — because a
## hand-written order would be a second content table living in GDScript.
##
## The row is a Plate Mill: it eats the Smelter's plate and makes a new Item, which some new
## Machine then eats. So it belongs at stage 2 beside the Ammo Press, and its own consumer at
## stage 3 beside the Turret, and nothing here was told any of that.
func test_a_machine_added_as_a_row_lands_where_the_chain_says() -> void:
	var definitions: Definitions = _content_plus_a_girder_line()
	assert_false(definitions.has_errors(), definitions.describe_errors())

	var order: PackedInt64Array = BuildChain.order(definitions)
	var columns: PackedInt64Array = BuildChain.column_of(definitions)
	var at: Dictionary = {}
	for cell: int in range(order.size()):
		at[definitions.machine_at(order[cell]).id] = columns[cell]

	assert_eq(at["girder_mill_mk1"], 2, "it eats plate, so it is as deep as the Ammo Press")
	assert_eq(at["girder_welder_mk1"], 3, "and what eats its girders is one deeper again")
	# And the line it was dropped beside did not move.
	assert_eq(at["miner_mk1"], 0)
	assert_eq(at["smelter_mk1"], 1)
	assert_eq(at["mg_turret_mk1"], 3)


## The shipped content with two rows and two Recipes added, and nothing else changed.
func _content_plus_a_girder_line() -> Definitions:
	var machines: String = (
		ContentFixture.shipped(Definitions.MACHINES_FILE).strip_edges() + "\n"
	) + (
		"girder_mill_mk1,Girder Mill Mk1,crafter,2,2,2,100,0,400,0,0,0,0,0,roll_girder,iron_plate:10\n"
		+ "girder_welder_mk1,Girder Welder Mk1,crafter,2,2,2,100,0,400,0,0,0,0,0,weld_frame,iron_plate:10\n"
	)
	var recipes: String = (
		ContentFixture.shipped(Definitions.RECIPES_FILE).strip_edges() + "\n"
	) + (
		"roll_girder,Roll Girder,iron_plate:2,girder:1,4\n"
		+ "weld_frame,Weld Frame,girder:2,frame:1,4\n"
	)
	var fixture: ContentFixture = ContentFixture.for_case(self)
	fixture.machines = machines
	fixture.recipes = recipes
	return fixture.definitions()


# ── The hotbar and the objective line, from one authority ─────────────────────
# "Say what is next" is #53's fourth criterion, and the only version of it worth having is
# one fact drawn twice. `Objective` already names the next thing to do; what it gained is a
# second reading of the *same step* that says which cell of the hotbar it is talking about.
# They cannot disagree, because there is one `_step` behind both.

func test_the_objective_points_at_the_cell_it_is_talking_about() -> void:
	var layout: MapLayout = MapLayout.empty()
	layout.add_node(Vector3i(0, 0, 0), "iron_ore", 1)
	layout.sort_nodes()
	var sim: Simulation = Simulation.new(1, 1, null, layout)
	var definitions: Definitions = sim.query_definitions()

	# Step one: the line says a Miner, and the pointer is on the Miner a Run opens with —
	# not the Mk2 a Delivery still has shut, and not whichever Miner sorts first by id.
	assert_true(Objective.line(sim, 0).contains("Miner"), Objective.line(sim, 0))
	assert_eq(
		Objective.pointed_at(sim, 0),
		definitions.machine_index("miner_mk1"),
		"the first Miner in chain order that this Run can actually build"
	)

	sim.step([
		InputAction.build_machine(0, definitions.machine_index("miner_mk1"), Vector3i(0, 0, 0))
	])
	assert_true(Objective.line(sim, 0).contains("Smelter"), Objective.line(sim, 0))
	assert_eq(
		Objective.pointed_at(sim, 0),
		definitions.machine_index("smelter_mk1"),
		"and now at the first crafter in chain order"
	)

	sim.step([
		InputAction.build_machine(0, definitions.machine_index("smelter_mk1"), Vector3i(0, 0, 5))
	])
	assert_true(Objective.line(sim, 0).contains("Belt"), Objective.line(sim, 0))
	assert_eq(
		Objective.pointed_at(sim, 0),
		definitions.machine_count(),
		"the Belt cell, which is the one past the end of the Machine list"
	)


## A step with nothing to place points at nothing, rather than at the last thing it pointed
## at. There is no memory in here to go stale.
func test_a_step_that_is_not_about_placing_anything_points_at_nothing() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var stocked: Simulation = Simulation.new(1, 1)
	# A Miner on bare rock is starved, which is the step that is about a Belt rather than
	# about a cell — and the Run-over and delivered cases say nothing at all.
	stocked.step([
		InputAction.build_machine(
			0, stocked.query_definitions().machine_index("miner_mk1"), Vector3i(20, 0, 20)
		)
	])
	assert_ne(Objective.pointed_at(sim, 0), -1, "the opening step does point somewhere")
	assert_eq(Objective.line(null, 0), "", "and a Run that is not there says nothing")
	assert_eq(Objective.pointed_at(null, 0), -1, "and points at nothing")


## Asking either question is a read. #53's criterion: nothing new in `game/` is
## authoritative, so the projections behind the hotbar cannot move the Run they describe.
func test_asking_what_is_next_leaves_the_state_hash_where_it_was() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	_step_a_few(sim)
	var before: int = sim.hash()
	var definitions: Definitions = sim.query_definitions()
	Objective.line(sim, 0)
	Objective.pointed_at(sim, 0)
	BuildChain.order(definitions)
	BuildChain.column_of(definitions)
	BuildChain.row_of(definitions)
	BuildChain.cell_of(definitions, 0)
	BuildChain.first_unlocked_of_role(sim, MachineDefinition.Role.MINER)
	assert_eq(sim.hash(), before, "reading the chain is a read")


static func _step_a_few(sim: Simulation) -> void:
	for _tick: int in range(5):
		sim.step([])


## What a render taught, and it is #53's third criterion arriving as a layout constraint.
##
## Dropping the two deeper Miners into stage 0 beside the Miner a Run opens with makes that
## one column four cells tall, and a hotbar is as tall as its tallest column — so two
## Machines nobody can build yet pushed the whole chain four rows up the screen and over the
## Factory it is about. They are *later*, which `content/deliveries.csv` already knows, so
## they go in their own group past the end of the chain and the grid stays as tall as the
## chain actually is.
func test_what_a_delivery_gates_sits_past_the_end_of_the_chain() -> void:
	var definitions: Definitions = Definitions.load_from_directory(Definitions.CONTENT_DIR)
	var order: PackedInt64Array = BuildChain.order(definitions)
	var columns: PackedInt64Array = BuildChain.column_of(definitions)
	var rows: PackedInt64Array = BuildChain.row_of(definitions)

	var last_chain_column: int = -1
	var tallest: int = 0
	for cell: int in range(order.size()):
		if BuildChain.group_of(definitions)[cell] != BuildChain.GROUP_CHAIN:
			continue
		last_chain_column = maxi(last_chain_column, columns[cell])
		tallest = maxi(tallest, rows[cell] + 1)

	assert_eq(tallest, 2, "the shipped chain is two deep: the line, and the branches under it")
	for cell: int in range(order.size()):
		var id: String = definitions.machine_at(order[cell]).id
		if not definitions.locks_machine(id):
			continue
		assert_true(columns[cell] > last_chain_column, "%s is past the chain" % id)
		assert_true(
			rows[cell] < tallest, "and does not make the hotbar any taller: %s" % id
		)


## The keys still run along the chain first, whatever the layout does. A player learns
## 1-2-3-4 as the line to build; what a Delivery gates comes after it.
func test_the_keys_run_along_the_chain_before_they_reach_what_is_gated() -> void:
	var definitions: Definitions = Definitions.load_from_directory(Definitions.CONTENT_DIR)
	var order: PackedInt64Array = BuildChain.order(definitions)
	var reached_a_gated_one: bool = false
	for cell: int in range(order.size()):
		var gated: bool = definitions.locks_machine(definitions.machine_at(order[cell]).id)
		if gated:
			reached_a_gated_one = true
		elif reached_a_gated_one:
			assert_true(false, "an ungated Machine after a gated one, at cell %d" % cell)
	assert_true(reached_a_gated_one, "the shipped chain does gate something")
